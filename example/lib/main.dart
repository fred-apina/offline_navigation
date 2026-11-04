import 'package:flutter/material.dart';
import 'package:offline_navigation/offline_navigation.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'offline_navigation demo',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const DemoHome(),
    );
  }
}

/// A preset A→B trip for the demo picker.
class _Trip {
  const _Trip(this.label, this.start, this.destination);
  final String label;
  final NavPoint start;
  final NavPoint destination;
}

const _trips = <_Trip>[
  _Trip(
    'Zürich HB → ETH Zürich',
    NavPoint(latitude: 47.3779, longitude: 8.5403, name: 'Zürich HB'),
    NavPoint(latitude: 47.3763, longitude: 8.5476, name: 'ETH Zürich'),
  ),
  _Trip(
    'Dodoma City → University of Dodoma',
    NavPoint(latitude: -6.1722, longitude: 35.7395, name: 'Dodoma City Centre'),
    NavPoint(latitude: -6.1841, longitude: 35.9297, name: 'University of Dodoma'),
  ),
  // Needs a region map that covers Serengeti National Park (see the README).
  _Trip(
    'Serengeti: Naabi Hill → Seronera',
    NavPoint(latitude: -2.8331, longitude: 34.9979, name: 'Naabi Hill'),
    NavPoint(latitude: -2.4467, longitude: 34.8191, name: 'Seronera'),
  ),
];

// Optional defaults for the region map form, e.g.
// flutter run --dart-define=REGION_ID=serengeti
//   --dart-define=REGION_URL=http://10.0.2.2:8765/serengeti.mwm
//   --dart-define=REGION_SHA256=<hex> --dart-define=REGION_SIZE=<bytes>
const _defaultRegionId = String.fromEnvironment('REGION_ID', defaultValue: 'serengeti');
const _defaultRegionUrl = String.fromEnvironment('REGION_URL');
const _defaultRegionSha = String.fromEnvironment('REGION_SHA256');
const _defaultRegionSize = String.fromEnvironment('REGION_SIZE');

class DemoHome extends StatefulWidget {
  const DemoHome({super.key});

  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  _Trip _trip = _trips.first;
  TravelMode _mode = TravelMode.drive;
  bool _voice = true;
  bool _simulate = true; // On by default so the demo works without real GPS.
  bool _installedOnly = false;
  NavigationResult? _lastResult;

  // Region maps.
  final _regionId = TextEditingController(text: _defaultRegionId);
  final _regionUrl = TextEditingController(text: _defaultRegionUrl);
  final _regionSha = TextEditingController(text: _defaultRegionSha);
  final _regionSize = TextEditingController(text: _defaultRegionSize);
  List<RegionMapInfo> _installed = const [];
  String _regionStatus = '';
  double? _regionProgress;
  bool _busy = false;
  MapInstallCancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _refreshInstalled();
  }

  @override
  void dispose() {
    for (final c in [_regionId, _regionUrl, _regionSha, _regionSize]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshInstalled() async {
    try {
      final maps = await OfflineNavigation.listRegionMaps();
      if (mounted) setState(() => _installed = maps);
    } on MapInstallException catch (e) {
      if (mounted) setState(() => _regionStatus = e.message);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _regionProgress = null;
    });
    try {
      await action();
    } on MapInstallException catch (e) {
      if (mounted) setState(() => _regionStatus = '${e.error.name}: ${e.message}');
    } finally {
      _cancelToken = null;
      if (mounted) setState(() => _busy = false);
      await _refreshInstalled();
    }
  }

  Future<void> _ensureBase() => _run(() async {
        setState(() => _regionStatus = 'Downloading the base world map…');
        await OfflineNavigation.ensureBaseMaps(
          onProgress: (p) => setState(() => _regionProgress = p / 100),
        );
        setState(() => _regionStatus = 'Base world map is installed.');
      });

  Future<void> _installRegion({bool replace = false}) => _run(() async {
        final token = _cancelToken = MapInstallCancelToken();
        setState(() => _regionStatus = 'Downloading…');
        final info = await OfflineNavigation.installRegionMap(
          RegionMapSource(
            id: _regionId.text.trim(),
            url: Uri.parse(_regionUrl.text.trim()),
            sha256: _regionSha.text.trim(),
            sizeBytes: int.tryParse(_regionSize.text.trim()),
          ),
          replace: replace,
          cancelToken: token,
          onProgress: (p) => setState(() => _regionProgress = p.fraction),
        );
        setState(() => _regionStatus = 'Installed ${info.id} (${(info.sizeBytes / 1048576).toStringAsFixed(1)} MB).');
      });

  Future<void> _removeRegion(String id) => _run(() async {
        await OfflineNavigation.removeRegionMap(id);
        setState(() => _regionStatus = 'Removed $id.');
      });

  Future<void> _navigate() async {
    final result = await Navigator.of(context).push<NavigationResult>(
      MaterialPageRoute(
        builder: (_) => OfflineNavigationPage(
          start: _trip.start,
          destination: _trip.destination,
          travelMode: _mode,
          options: NavOptions(
            voiceGuidance: _voice,
            simulateRoute: _simulate,
            mapPolicy: _installedOnly ? MapPolicy.installedOnly : MapPolicy.autoDownloadCountry,
          ),
        ),
      ),
    );
    if (mounted) setState(() => _lastResult = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('offline_navigation demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Route', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final trip in _trips)
            ListTile(
              leading: Icon(
                _trip == trip
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: _trip == trip ? Theme.of(context).colorScheme.primary : null,
              ),
              title: Text(trip.label),
              subtitle: Text('${trip.start.name} → ${trip.destination.name}'),
              onTap: () => setState(() => _trip = trip),
            ),
          const Divider(height: 32),
          Text('Travel mode', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<TravelMode>(
            segments: const [
              ButtonSegment(value: TravelMode.drive, icon: Icon(Icons.directions_car), label: Text('Drive')),
              ButtonSegment(value: TravelMode.walk, icon: Icon(Icons.directions_walk), label: Text('Walk')),
              ButtonSegment(value: TravelMode.cycle, icon: Icon(Icons.directions_bike), label: Text('Cycle')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Voice guidance'),
            value: _voice,
            onChanged: (v) => setState(() => _voice = v),
          ),
          SwitchListTile(
            title: const Text('Simulate movement'),
            subtitle: const Text('Drive the route automatically (no real GPS needed)'),
            value: _simulate,
            onChanged: (v) => setState(() => _simulate = v),
          ),
          SwitchListTile(
            title: const Text('Installed maps only'),
            subtitle: const Text('Never download map data; use what is on the device'),
            value: _installedOnly,
            onChanged: (v) => setState(() => _installedOnly = v),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _navigate,
            icon: const Icon(Icons.navigation),
            label: const Text('Start offline navigation'),
          ),
          if (_lastResult != null) ...[
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: Icon(switch (_lastResult!.outcome) {
                  NavigationOutcome.arrived => Icons.check_circle,
                  NavigationOutcome.cancelledByUser => Icons.cancel,
                  NavigationOutcome.failed => Icons.error,
                }),
                title: Text('Last result: ${_lastResult!.outcome.name}'),
                subtitle: Text([
                  if (_lastResult!.failure != null) _lastResult!.failure!.name,
                  if (_lastResult!.missingMaps.isNotEmpty) 'missing: ${_lastResult!.missingMaps.join(', ')}',
                  if (_lastResult!.message != null) _lastResult!.message!,
                ].join(' · ')),
              ),
            ),
          ],
          const Divider(height: 48),
          Text('Region maps', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Install a map file for one area (a park, a city…) ahead of time, then navigate there '
            'with "Installed maps only" and no internet.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _ensureBase,
            icon: const Icon(Icons.public),
            label: const Text('Download base world map'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regionId,
            decoration: const InputDecoration(labelText: 'Id', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _regionUrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'URL of the .mwm file', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _regionSha,
            decoration: const InputDecoration(labelText: 'SHA-256', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _regionSize,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Size in bytes (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _installRegion(),
                  icon: const Icon(Icons.download),
                  label: const Text('Install'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _busy ? null : () => _installRegion(replace: true),
                child: const Text('Replace'),
              ),
              if (_busy && _cancelToken != null) ...[
                const SizedBox(width: 8),
                TextButton(onPressed: _cancelToken!.cancel, child: const Text('Cancel')),
              ],
            ],
          ),
          if (_busy) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(value: _regionProgress),
          ),
          if (_regionStatus.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_regionStatus)),
          const SizedBox(height: 8),
          if (_installed.isEmpty)
            const Text('No region maps installed.')
          else
            for (final map in _installed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.map),
                title: Text(map.id),
                subtitle: Text('${(map.sizeBytes / 1048576).toStringAsFixed(1)} MB'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : () => _removeRegion(map.id),
                ),
              ),
        ],
      ),
    );
  }
}
