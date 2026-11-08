// On-device test of region maps: install a map for one area, then route inside
// it using only what is on the device.
//
// Serve the map file from your machine and forward the port to the device:
//
//   python3 -m http.server 8765 --bind 127.0.0.1 --directory <dir with the .mwm>
//   adb reverse tcp:8765 tcp:8765
//
// Phase 1 needs the network (base world map + download). Phase 2 is meant to be
// run afterwards with airplane mode on, to show that nothing else is needed:
//
//   flutter test integration_test/region_maps_test.dart -d <device> \
//     --dart-define=PHASE=install   --dart-define=REGION_URL=http://localhost:8765/serengeti.mwm \
//     --dart-define=REGION_SHA256=<hex> --dart-define=REGION_SIZE=<bytes>
//   adb shell cmd connectivity airplane-mode enable
//   flutter test integration_test/region_maps_test.dart -d <device> --dart-define=PHASE=navigate
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_navigation/offline_navigation.dart';

const _id = String.fromEnvironment('REGION_ID', defaultValue: 'serengeti');
const _url = String.fromEnvironment('REGION_URL');
const _sha = String.fromEnvironment('REGION_SHA256');
const _size = int.fromEnvironment('REGION_SIZE');

// Without a server (a physical iPhone, which cannot reach one reliably): copy the map into the app's Documents
// folder over USB,
//   xcrun devicectl device copy to --device <udid> --source serengeti.mwm --destination Documents/serengeti.mwm \
//     --domain-type appDataContainer --domain-identifier <bundle id>
// and run with REGION_FILE=serengeti.mwm instead of REGION_URL. The map then goes through
// installRegionMapFromFile, the call the downloader itself ends with.
const _regionFile = String.fromEnvironment('REGION_FILE');
bool get _fromFile => _regionFile.isNotEmpty;
// The app's temp folder is a sibling of its Documents folder (an iPhone app has no HOME variable).
String get _filePath => '${Directory.systemTemp.parent.path}/Documents/$_regionFile';

Future<RegionMapInfo> _installRegion({String id = _id, String? sha256}) {
  if (_fromFile) return OfflineNavigation.installRegionMapFromFile(id, _filePath, sha256: sha256 ?? _sha);
  return OfflineNavigation.installRegionMap(RegionMapSource(
      id: id, url: Uri.parse(_url), sha256: sha256 ?? _sha, sizeBytes: _size > 0 ? _size : null));
}
const _phase = String.fromEnvironment('PHASE', defaultValue: 'all');

// For a one-run proof: after the install the test prints READY_FOR_OFFLINE and
// waits this many seconds, during which the host turns airplane mode on. The
// navigation tests then assert that the network is really unreachable.
const _offlineDelaySeconds = int.fromEnvironment('OFFLINE_DELAY');
const _requireOffline = bool.fromEnvironment('REQUIRE_OFFLINE');

// Run without ever fetching the base world map (World.mwm/WorldCoasts.mwm,
// 72 MB): the park-only case. Every assertion below must still hold.
const _skipBaseMaps = bool.fromEnvironment('SKIP_BASE_MAPS');

// Spoken turn instructions during the guidance tests (VOICE=true). Off by default: a CI run has nobody to listen,
// but it still exercises the engine's notification path, which is worth a run on every new platform or engine.
const _voice = bool.fromEnvironment('VOICE');

// Seconds to stand still on the route preview and on the guidance screen, so
// the host can take a screenshot (it waits for the PREVIEW_READY and
// GUIDANCE_STARTED lines).
const _holdSeconds = int.fromEnvironment('HOLD_SECONDS');

Future<bool> _networkReachable() async {
  try {
    final socket = await Socket.connect('1.1.1.1', 443, timeout: const Duration(seconds: 3));
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

// Inside Serengeti National Park.
const _naabiHill = NavPoint(latitude: -2.8331, longitude: 34.9979, name: 'Naabi Hill');
const _seronera = NavPoint(latitude: -2.4467, longitude: 34.8191, name: 'Seronera');
// Dodoma: far outside the region map.
const _dodoma = NavPoint(latitude: -6.1722, longitude: 35.7395, name: 'Dodoma');
const _udom = NavPoint(latitude: -6.1841, longitude: 35.9297, name: 'UDOM');
// A short drive inside the region (about 7 km), for the first-open preview test.
const _viboko =
    NavPoint(latitude: -2.4935686, longitude: 34.8302072, name: 'Bwawa La Viboko Vya Naabi');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('install', () {
    testWidgets('downloads, verifies and installs a region map', (tester) async {
      expect(_fromFile || _url.isNotEmpty, isTrue, reason: 'pass --dart-define=REGION_URL=... or REGION_FILE=...');
      expect(_sha, isNotEmpty, reason: 'pass --dart-define=REGION_SHA256=...');

      await OfflineNavigation.initialize();
      debugPrint('engine data version: ${await OfflineNavigation.engineDataVersion}');

      if (_skipBaseMaps) {
        expect(await OfflineNavigation.baseMapsBytesMissing, greaterThan(0),
            reason: 'this run has to start without the base world map');
      } else {
        await OfflineNavigation.ensureBaseMaps();
        expect(await OfflineNavigation.baseMapsBytesMissing, 0);
      }

      await OfflineNavigation.removeRegionMap(_id);
      expect(await OfflineNavigation.isRegionMapInstalled(_id), isFalse);

      final progress = <double?>[];
      final info = _fromFile
          ? await _installRegion()
          : await OfflineNavigation.installRegionMap(
              RegionMapSource(
                id: _id,
                url: Uri.parse(_url),
                sha256: _sha,
                sizeBytes: _size > 0 ? _size : null,
              ),
              onProgress: (p) => progress.add(p.fraction),
            );
      debugPrint('installed: $info');
      expect(info.id, _id);
      if (_size > 0) expect(info.sizeBytes, _size);
      if (!_fromFile) expect(progress, isNotEmpty);
      expect(await OfflineNavigation.isRegionMapInstalled(_id), isTrue);
      expect(await OfflineNavigation.listRegionMaps(), contains(info));

      if (_offlineDelaySeconds > 0) {
        debugPrint('READY_FOR_OFFLINE');
        await Future<void>.delayed(const Duration(seconds: _offlineDelaySeconds));
      }
    }, skip: _phase == 'navigate');

    // Removing a map rebuilds the router, which still lists the removed map. That used to abort the
    // engine whenever the map was not in use at that moment.
    testWidgets('removes an installed map and installs it again, twice', (tester) async {
      await OfflineNavigation.initialize();
      for (var round = 0; round < 2; round++) {
        await OfflineNavigation.removeRegionMap(_id);
        expect(await OfflineNavigation.isRegionMapInstalled(_id), isFalse, reason: 'round $round: removed');
        expect(await OfflineNavigation.listRegionMaps(), isEmpty, reason: 'round $round: none listed');
        await _installRegion();
        expect(await OfflineNavigation.isRegionMapInstalled(_id), isTrue, reason: 'round $round: installed again');
      }
    }, skip: _phase == 'navigate');

    testWidgets('refuses bad requests without touching installed maps', (tester) async {
      await OfflineNavigation.initialize();
      final before = await OfflineNavigation.listRegionMaps();

      Future<MapInstallError?> errorOf(Future<void> Function() action) async {
        try {
          await action();
        } on MapInstallException catch (e) {
          return e.error;
        }
        return null;
      }

      expect(await errorOf(() => _installRegion()), MapInstallError.alreadyInstalled);
      expect(await errorOf(() => _installRegion(id: '../x')), MapInstallError.invalidId);
      expect(await errorOf(() => OfflineNavigation.installRegionMapFromFile('World', '/nonexistent')),
          MapInstallError.reservedName);
      expect(await errorOf(() => OfflineNavigation.installRegionMapFromFile('Tanzania', '/nonexistent')),
          anyOf(MapInstallError.reservedName, MapInstallError.fileNotFound));
      expect(await errorOf(() => OfflineNavigation.installRegionMapFromFile('ghost', '/nonexistent')),
          MapInstallError.fileNotFound);

      // A wrong checksum must be rejected and must leave nothing behind.
      expect(await errorOf(() => _installRegion(id: 'wronghash', sha256: '0' * 64)),
          MapInstallError.checksumMismatch);
      expect(await OfflineNavigation.isRegionMapInstalled('wronghash'), isFalse);

      expect(await OfflineNavigation.listRegionMaps(), before);
    }, skip: _phase == 'navigate');
  });

  group('navigate', () {
    testWidgets('the device has no network when it is required to be offline', (tester) async {
      expect(await _networkReachable(), isFalse, reason: 'the proof is only valid offline');
    }, skip: !_requireOffline);

    Future<NavigationResult?> runPage(
      WidgetTester tester,
      NavPoint start,
      NavPoint destination, {
      required bool Function() stop,
      Future<void> Function()? onPreview,
    }) async {
      final done = Completer<NavigationResult?>();
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final result = await Navigator.of(context).push<NavigationResult>(
                    MaterialPageRoute(
                      builder: (_) => OfflineNavigationPage(
                        start: start,
                        destination: destination,
                        options: const NavOptions(
                          mapPolicy: MapPolicy.installedOnly,
                          simulateRoute: true,
                          voiceGuidance: _voice,
                        ),
                      ),
                    ),
                  );
                  done.complete(result);
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));

      // pumpAndSettle would never return: the page shows spinners and a map.
      for (var i = 0; i < 1200 && !done.isCompleted && !stop(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      debugPrint('page shows: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().join(' | ')}');
      if (onPreview != null && !done.isCompleted) {
        // The loop above stops the moment the route is shown, with the page still sliding in (iOS pushes a page over
        // half a second, and it only moves while the test pumps frames). Let it settle, so a hold, a screenshot or a
        // person watching sees the real page and not a half-open one.
        await tester.pump(const Duration(seconds: 1));
        await onPreview();
      }
      return done.isCompleted ? done.future : null;
    }

    // Keep this the FIRST test that opens the page. The bug it covers only
    // happens on the first open after the app starts: a short route is built
    // before the map has a drawing engine, so the engine could not zoom to it
    // and the preview came up zoomed far out (blank without the base maps).
    // tool/check_preview_framing.sh takes a screenshot at SHORT_PREVIEW_READY and
    // checks that the map is really drawn.
    testWidgets('frames a short route on the very first open', (tester) async {
      await OfflineNavigation.initialize();
      expect(await OfflineNavigation.isRegionMapInstalled(_id), isTrue,
          reason: 'run the install phase first');

      final result = await runPage(
        tester,
        _seronera,
        _viboko,
        stop: () => find.text('Start navigation').evaluate().isNotEmpty,
        onPreview: () async {
          debugPrint('SHORT_PREVIEW_READY');
          // Hold still: the host takes its screenshot a few seconds after the line above.
          await tester.pump(const Duration(seconds: 10));
          await tester.tap(find.byIcon(Icons.close));
          await tester.pump(const Duration(seconds: 1));
        },
      );
      expect(result?.outcome, NavigationOutcome.cancelledByUser,
          reason: 'no route preview was reached; page result: $result');
    });

    testWidgets('routes inside the installed region with no network', (tester) async {
      await OfflineNavigation.initialize();
      expect(await OfflineNavigation.isRegionMapInstalled(_id), isTrue,
          reason: 'run the install phase first');

      String? distance;
      final result = await runPage(
        tester,
        _naabiHill,
        _seronera,
        stop: () => find.text('Start navigation').evaluate().isNotEmpty,
        onPreview: () async {
          expect(find.text('Start navigation'), findsOneWidget);
          distance = tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data)
              .whereType<String>()
              .join(' | ');
          debugPrint('route preview: $distance');
          await tester.tap(find.byIcon(Icons.close));
          await tester.pump(const Duration(seconds: 1));
        },
      );
      expect(distance, isNotNull, reason: 'no route preview; page result: $result');
      expect(RegExp(r'\d+([.,]\d+)? ?(km|m)\b').hasMatch(distance!), isTrue,
          reason: 'the preview should show a distance: $distance');
      expect(result?.outcome, NavigationOutcome.cancelledByUser);
      if (_skipBaseMaps) {
        expect(await OfflineNavigation.baseMapsBytesMissing, greaterThan(0),
            reason: 'installedOnly must not fetch the base world map');
      }
    });

    testWidgets('starts turn-by-turn guidance inside the installed region', (tester) async {
      await OfflineNavigation.initialize();
      expect(await OfflineNavigation.isRegionMapInstalled(_id), isTrue,
          reason: 'run the install phase first');

      String? guidance;
      final result = await runPage(
        tester,
        _naabiHill,
        _seronera,
        stop: () => find.text('Start navigation').evaluate().isNotEmpty,
        onPreview: () async {
          debugPrint('PREVIEW_READY');
          await tester.pump(const Duration(seconds: _holdSeconds));
          await tester.tap(find.text('Start navigation'));
          // Guidance is running once the preview is gone and the End button is up.
          for (var i = 0; i < 200 && find.text('End').evaluate().isEmpty; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          // Let the simulated drive move for a while.
          await tester.pump(const Duration(seconds: 15));
          guidance = tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data)
              .whereType<String>()
              .join(' | ');
          debugPrint('guidance: $guidance');
          debugPrint('GUIDANCE_STARTED');
          await tester.pump(const Duration(seconds: _holdSeconds));
          expect(find.text('End'), findsOneWidget);
          await tester.tap(find.text('End'));
          await tester.pump(const Duration(seconds: 1));
        },
      );
      expect(guidance, isNotNull, reason: 'no route preview; page result: $result');
      expect(guidance!, contains('End'));
      expect(guidance!, isNot(contains('Start navigation')));
      expect(result?.outcome, NavigationOutcome.cancelledByUser);
      if (_skipBaseMaps) {
        expect(await OfflineNavigation.baseMapsBytesMissing, greaterThan(0));
      }
    });

    // Needs VOICE=true. The route is short and has a turn soon after the start, so a spoken instruction is due.
    // The test cannot hear it; the host checks the device log (iOS: "offline_navigation: speaking").
    testWidgets('speaks turn instructions while guiding', (tester) async {
      await OfflineNavigation.initialize();
      var guided = false;
      await runPage(
        tester,
        _seronera,
        _viboko,
        stop: () => find.text('Start navigation').evaluate().isNotEmpty,
        onPreview: () async {
          await tester.pump(const Duration(seconds: 1));
          await tester.tap(find.text('Start navigation'));
          for (var i = 0; i < 200 && find.text('End').evaluate().isEmpty; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          // About 15 m/s simulated: the first turn is reached well within this.
          await tester.pump(const Duration(seconds: 90));
          guided = find.text('End').evaluate().isNotEmpty;
          debugPrint('VOICE_GUIDANCE_DONE');
          if (guided) await tester.tap(find.text('End'));
          await tester.pump(const Duration(seconds: 1));
        },
      );
      expect(guided, isTrue);
    }, skip: !_voice);

    testWidgets('reports missing maps instead of downloading outside the region', (tester) async {
      await OfflineNavigation.initialize();
      final result = await runPage(tester, _dodoma, _udom, stop: () => false);
      debugPrint('outside the region: $result missing=${result?.missingMaps}');
      expect(result, isNotNull, reason: 'the page must pop by itself');
      expect(result!.outcome, NavigationOutcome.failed);
      expect(result.failure, NavigationFailure.mapsMissing);
      expect(result.missingMaps, isNotEmpty);
    });
  });
}
