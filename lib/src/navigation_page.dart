import 'dart:async';
import 'dart:io' show HttpClient;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;

import 'channels.dart';
import 'map_view.dart';
import 'models.dart';
import 'turn_icons.dart';

/// A self-contained offline turn-by-turn navigation page.
///
/// Push it onto the navigator; it manages its own flow — downloading the
/// required country map (if missing), building the route, showing a preview,
/// then guiding — and pops with a [NavigationResult] when finished.
///
/// ```dart
/// final result = await Navigator.push<NavigationResult>(
///   context,
///   MaterialPageRoute(builder: (_) => OfflineNavigationPage(
///     start: NavPoint(latitude: ..., longitude: ..., name: 'A'),
///     destination: NavPoint(latitude: ..., longitude: ..., name: 'B'),
///   )),
/// );
/// ```
class OfflineNavigationPage extends StatefulWidget {
  const OfflineNavigationPage({
    super.key,
    required this.start,
    required this.destination,
    this.travelMode = TravelMode.drive,
    this.options = const NavOptions(),
  });

  final NavPoint start;
  final NavPoint destination;
  final TravelMode travelMode;
  final NavOptions options;

  @override
  State<OfflineNavigationPage> createState() => _OfflineNavigationPageState();
}

enum _Phase { initializing, downloading, buildingRoute, preview, navigating, error }

class _OfflineNavigationPageState extends State<OfflineNavigationPage> {
  _Phase _phase = _Phase.initializing;
  String _statusText = 'Starting…';
  String? _errorMessage;

  // Download state.
  final List<String> _countriesToDownload = [];
  int _downloadProgress = 0;
  bool _downloadingBaseMaps = false;
  StreamSubscription<MapDownloadEvent>? _downloadSub;
  VoidCallback? _errorRetry;

  // Route/guidance state.
  RouteSummary? _summary;
  GuidanceUpdate? _guidance;
  StreamSubscription<GuidanceUpdate>? _guidanceSub;
  bool _mapReady = false;
  Timer? _slowBuildTimer;
  bool _slowBuild = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _slowBuildTimer?.cancel();
    _downloadSub?.cancel();
    _guidanceSub?.cancel();
    // Stop any in-flight downloads: leaving them running after the user backs
    // out would silently keep consuming bandwidth. Both cancels are no-ops
    // when nothing is downloading. Partial files resume on the next attempt.
    if (_phase == _Phase.downloading) {
      if (_downloadingBaseMaps) {
        unawaited(NavChannel.cancelBaseMapDownload());
      } else if (_countriesToDownload.isNotEmpty) {
        unawaited(NavChannel.cancelDownload(List.of(_countriesToDownload)));
      }
    }
    // Best-effort: tear down the native route so the next page starts clean.
    unawaited(NavChannel.closeRouting());
    unawaited(NavChannel.setKeepScreenOn(false));
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      _setStatus('Initializing map engine…');
      await NavChannel.initialize();
      setState(() => _mapReady = true);
      if (!await _ensureBaseMaps()) return;
      await _ensureMaps();
    } catch (e) {
      _fail('Could not start navigation: $e', retry: _restart);
    }
  }

  /// Re-runs the whole bootstrap after a failure. Every step is idempotent:
  /// engine init resolves immediately once ready, and downloads skip
  /// already-present files.
  void _restart() {
    setState(() {
      _phase = _Phase.initializing;
      _errorMessage = null;
      _errorRetry = null;
    });
    _bootstrap();
  }

  // ── Map data ────────────────────────────────────────────────

  /// Downloads World.mwm/WorldCoasts.mwm on first run. Without them the map
  /// is blank outside downloaded countries. Returns false if the flow should
  /// stop (failure or cancellation).
  Future<bool> _ensureBaseMaps() async {
    _setStatus('Checking base world map…');
    final missingBytes = await NavChannel.getBaseMapBytes();
    if (missingBytes <= 0) return true;

    setState(() {
      _phase = _Phase.downloading;
      _downloadingBaseMaps = true;
      _downloadProgress = 0;
    });
    _downloadSub?.cancel();
    _downloadSub = NavChannel.downloadEvents().listen((event) {
      if (event.countryId == NavChannel.baseMapId && event.progress >= 0) {
        setState(() => _downloadProgress = event.progress);
      }
    });

    try {
      await NavChannel.downloadBaseMaps();
      return true;
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') return false; // user cancelled; page is closing
      await _failDownload(e.message ?? 'Could not download the base world map');
      return false;
    } finally {
      _downloadSub?.cancel();
      if (mounted) setState(() => _downloadingBaseMaps = false);
    }
  }

  /// Reports a download failure, distinguishing "this build's map data has
  /// been retired from the CDN" (permanent — needs an app update, no point
  /// retrying) from an ordinary network failure (retryable).
  ///
  /// Organic Maps serves map files under a dated data version
  /// (`.../maps/<version>/<file>`) and eventually removes old versions. A tiny
  /// probe of a known file for this build's version tells the two cases apart:
  /// a 404 while the CDN is reachable means the version is gone.
  Future<void> _failDownload(String genericMessage) async {
    String message = genericMessage;
    VoidCallback? retry = _restart;
    try {
      final version = await NavChannel.getDataVersion();
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      try {
        final request = await client.headUrl(
            Uri.parse('https://cdn.organicmaps.app/maps/$version/WorldCoasts.mwm'));
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == 404) {
          message = 'The offline map data used by this version of the app is no '
              'longer available online. Please update the app to restore map '
              'downloads.';
          retry = null; // retrying cannot help
        }
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      // CDN unreachable or version lookup failed: treat as a transient
      // network problem and keep the generic, retryable error.
    }
    _fail(message, retry: retry);
  }

  Future<void> _ensureMaps() async {
    _setStatus('Checking offline maps…');
    final needed = <String>{};
    for (final point in [widget.start, widget.destination]) {
      final country = await NavChannel.resolveCountry(point.latitude, point.longitude);
      if (country != null && country.isNotEmpty) {
        final status = await NavChannel.getCountryStatus(country);
        if (!MapStatus.isDownloaded(status)) needed.add(country);
      }
    }

    if (needed.isEmpty) {
      await _buildRoute();
      return;
    }

    _countriesToDownload
      ..clear()
      ..addAll(needed);
    await _startDownload();
  }

  Future<void> _startDownload() async {
    setState(() {
      _phase = _Phase.downloading;
      _downloadProgress = 0;
    });
    _downloadSub?.cancel();
    _downloadSub = NavChannel.downloadEvents().listen(_onDownloadEvent);
    await NavChannel.startDownload(_countriesToDownload);
  }

  void _onDownloadEvent(MapDownloadEvent event) {
    if (!_countriesToDownload.contains(event.countryId)) return;
    if (event.status == MapStatus.failed) {
      unawaited(_failDownload('Map download failed for ${event.countryId}'));
      return;
    }
    // progress == -1 is a status-only event with no byte progress; keep the last value.
    if (event.progress >= 0) {
      setState(() => _downloadProgress = event.progress);
    }

    if (MapStatus.isDownloaded(event.status)) {
      setState(() => _downloadProgress = 100);
      _countriesToDownload.remove(event.countryId);
      if (_countriesToDownload.isEmpty) {
        _downloadSub?.cancel();
        unawaited(_buildRoute());
      }
    }
  }

  Future<void> _cancelDownload() async {
    if (_downloadingBaseMaps) {
      await NavChannel.cancelBaseMapDownload();
    } else {
      await NavChannel.cancelDownload(_countriesToDownload);
    }
    if (mounted) _close(const NavigationResult(NavigationOutcome.cancelledByUser));
  }

  // ── Routing ─────────────────────────────────────────────────

  Future<void> _buildRoute() async {
    setState(() {
      _phase = _Phase.buildingRoute;
      _statusText = 'Building route…';
      _slowBuild = false;
    });
    // Route calculation for very large regions can take minutes on first use
    // (the whole routing graph is loaded from disk). Surface a hint so the
    // wait doesn't read as a hang.
    _slowBuildTimer?.cancel();
    _slowBuildTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _phase == _Phase.buildingRoute) setState(() => _slowBuild = true);
    });

    await NavChannel.setViewport(widget.start.latitude, widget.start.longitude, 14);

    final result = await NavChannel.buildRoute(
      start: widget.start,
      destination: widget.destination,
      mode: widget.travelMode,
    );
    _slowBuildTimer?.cancel();
    if (!mounted) return;

    if (!result.ok) {
      if (result.cancelled) return; // the page is closing
      if (result.missingMaps.isNotEmpty) {
        // The route crosses regions we don't have yet — download them and retry.
        _countriesToDownload
          ..clear()
          ..addAll(result.missingMaps);
        await _startDownload();
        return;
      }
      _fail('Could not build a route (error ${result.errorCode})', retry: _restart);
      return;
    }

    setState(() {
      _summary = RouteSummary(
        distanceText: _formatDistance(result.distanceText, result.distanceUnits),
        duration: Duration(seconds: result.timeSeconds),
      );
      _phase = _Phase.preview;
    });
  }

  Future<void> _cancelRouteBuild() async {
    // Completes the in-flight build as cancelled on the native side.
    await NavChannel.closeRouting();
    if (mounted) _close(const NavigationResult(NavigationOutcome.cancelledByUser));
  }

  Future<void> _startGuidance() async {
    // Live guidance follows the device GPS, which needs location permission.
    // Simulated guidance drives itself and works without it.
    if (!widget.options.simulateRoute) {
      final granted = await NavChannel.requestLocationPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Location permission is required for turn-by-turn navigation.'),
          ));
        }
        return; // stay on the preview so the user can try again
      }
    }

    _guidanceSub?.cancel();
    _guidanceSub = NavChannel.guidanceEvents().listen(_onGuidance);
    try {
      await NavChannel.startGuidance(
        simulate: widget.options.simulateRoute,
        voice: widget.options.voiceGuidance,
      );
    } on PlatformException catch (e) {
      _guidanceSub?.cancel();
      if (e.code == 'no_route') {
        // The engine dropped the route behind our back (e.g. a stray position
        // triggered a rebuild that failed). Build it again, back to preview.
        await _buildRoute();
      } else {
        _fail('Could not start navigation: ${e.message ?? e.code}');
      }
      return;
    }
    unawaited(NavChannel.setKeepScreenOn(true));
    setState(() => _phase = _Phase.navigating);
  }

  void _onGuidance(GuidanceUpdate update) {
    setState(() => _guidance = update);
    // Arrival: the engine reports the destination turn for the whole final
    // approach (hundreds of meters out), so it alone must not end navigation.
    // Require the route to be essentially complete as well. completionPercent
    // is 0–100.
    final arrived =
        (update.turn == CarTurn.reachedYourDestination && update.completionPercent >= 95) ||
            update.completionPercent >= 99.5;
    if (arrived) {
      _guidanceSub?.cancel();
      _close(const NavigationResult(NavigationOutcome.arrived));
    }
  }

  // ── Helpers ─────────────────────────────────────────────────

  void _setStatus(String text) => setState(() => _statusText = text);

  void _fail(String message, {VoidCallback? retry}) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _errorMessage = message;
      _errorRetry = retry;
    });
  }

  bool _closing = false;

  void _close(NavigationResult result) {
    if (!mounted || _closing) return;
    _closing = true;
    // Use pop(), not maybePop(): PopScope(canPop: false) below intercepts maybePop
    // (and the system back gesture) but an explicit pop() dismisses the page.
    Navigator.of(context).pop(result);
  }

  static String _formatDistance(String? value, String? units) {
    if (value == null || value.isEmpty) return '—';
    return '$value ${_unitSuffix(units)}'.trim();
  }

  static String _unitSuffix(String? unitsName) => switch (unitsName) {
        'Meters' => 'm',
        'Kilometers' => 'km',
        'Feet' => 'ft',
        'Miles' => 'mi',
        _ => '',
      };

  // ── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _close(const NavigationResult(NavigationOutcome.cancelledByUser));
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_mapReady) const OfflineMapView() else const ColoredBox(color: Color(0xFFE8E6DE)),
              _buildOverlay(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    switch (_phase) {
      case _Phase.initializing:
        return _CenteredStatus(text: _statusText);
      case _Phase.buildingRoute:
        return _CenteredStatus(
          text: _statusText,
          subtext: _slowBuild
              ? 'Large regions can take a few minutes on first use'
              : null,
          onCancel: _cancelRouteBuild,
        );
      case _Phase.downloading:
        return _DownloadPanel(
          label: _downloadingBaseMaps
              ? 'World base map (first run)'
              : _countriesToDownload.join(', '),
          progress: _downloadProgress,
          onCancel: _cancelDownload,
        );
      case _Phase.preview:
        return _PreviewPanel(
          summary: _summary!,
          start: widget.start,
          destination: widget.destination,
          onStart: _startGuidance,
          onCancel: () => _close(const NavigationResult(NavigationOutcome.cancelledByUser)),
        );
      case _Phase.navigating:
        return _GuidanceChrome(
          guidance: _guidance,
          destinationName: widget.destination.name,
          onStop: () async {
            await NavChannel.stopGuidance();
            _close(const NavigationResult(NavigationOutcome.cancelledByUser));
          },
        );
      case _Phase.error:
        return _ErrorPanel(
          message: _errorMessage ?? 'Something went wrong',
          onRetry: _errorRetry,
          onClose: () => _close(NavigationResult(NavigationOutcome.failed, _errorMessage)),
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Overlays
// ─────────────────────────────────────────────────────────────

class _CenteredStatus extends StatelessWidget {
  const _CenteredStatus({required this.text, this.subtext, this.onCancel});
  final String text;
  final String? subtext;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(text, style: Theme.of(context).textTheme.titleMedium),
            if (subtext != null) ...[
              const SizedBox(height: 8),
              Text(
                subtext!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (onCancel != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
            ],
          ],
        ),
      ),
    );
  }
}

class _DownloadPanel extends StatelessWidget {
  const _DownloadPanel({
    required this.label,
    required this.progress,
    required this.onCancel,
  });

  final String label;
  final int progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: _BottomCard(
        children: [
          Row(
            children: [
              const Icon(Icons.download_for_offline_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Downloading offline map',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Text('$progress%', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress <= 0 ? null : progress / 100,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ),
        ],
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.summary,
    required this.start,
    required this.destination,
    required this.onStart,
    required this.onCancel,
  });

  final RouteSummary summary;
  final NavPoint start;
  final NavPoint destination;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 8,
          left: 8,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            shape: const CircleBorder(),
            elevation: 2,
            child: IconButton(icon: const Icon(Icons.close), onPressed: onCancel),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _BottomCard(
            children: [
              Row(
                children: [
                  _Stat(label: 'Distance', value: summary.distanceText),
                  const SizedBox(width: 24),
                  _Stat(label: 'Duration', value: _fmtDuration(summary.duration)),
                ],
              ),
              const SizedBox(height: 8),
              _Endpoint(icon: Icons.trip_origin, text: start.name ?? 'Start'),
              _Endpoint(icon: Icons.place, text: destination.name ?? 'Destination'),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.navigation),
                  label: const Text('Start navigation'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GuidanceChrome extends StatelessWidget {
  const _GuidanceChrome({
    required this.guidance,
    required this.destinationName,
    required this.onStop,
  });

  final GuidanceUpdate? guidance;
  final String? destinationName;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final g = guidance;
    return Column(
      children: [
        // Instruction banner.
        Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(turnIcon(g?.turn ?? CarTurn.goStraight),
                  size: 44, color: Theme.of(context).colorScheme.onPrimary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g == null || g.distanceToTurnText.isEmpty ? '—' : g.distanceToTurnText,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      g?.nextStreet.isNotEmpty == true ? g!.nextStreet : (destinationName ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // ETA bar.
        Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g == null ? '—' : _fmtDuration(g.timeRemaining),
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(g?.distanceToTargetText ?? '',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onStop,
                icon: const Icon(Icons.close),
                label: const Text('End'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onClose, this.onRetry});
  final String message;
  final VoidCallback onClose;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _BottomCard(
        children: [
          Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (onRetry != null) ...[
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                const SizedBox(width: 12),
              ],
              OutlinedButton(onPressed: onClose, child: const Text('Close')),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Small shared widgets
// ─────────────────────────────────────────────────────────────

class _BottomCard extends StatelessWidget {
  const _BottomCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(maxWidth: 480),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black26)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Endpoint extends StatelessWidget {
  const _Endpoint({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

String _fmtDuration(Duration d) {
  if (d.inMinutes < 1) return '<1 min';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return h > 0 ? '${h}h ${m}m' : '$m min';
}
