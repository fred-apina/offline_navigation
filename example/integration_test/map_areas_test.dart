// On-device test of the engine's own downloadable maps (map areas), the default flow of OfflineNavigationPage:
// which area covers a point and how big it is, what a trip would download, asking before it does, and downloading
// ahead of time. Nothing here installs a region map.
//
// The first group needs no network and no map on the device. The network tests download for real (tens of MB from
// the map server), so each is opt-in and meant for a clean device or simulator:
//
//   flutter test integration_test/map_areas_test.dart -d <device> --dart-define=NETWORK_TEST=base
//   flutter test integration_test/map_areas_test.dart -d <device> --dart-define=NETWORK_TEST=area
//   flutter test integration_test/map_areas_test.dart -d <device> --dart-define=NETWORK_TEST=page
//
//   base  asking how much of the base world map is missing while it downloads must not stop it
//   area  OfflineNavigation.downloadMapArea of one region
//   page  a trip with NavOptions(askBeforeDownload: true): ask, confirm, download, route preview
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_navigation/offline_navigation.dart';
import 'package:offline_navigation/src/channels.dart';

const _network = String.fromEnvironment('NETWORK_TEST');

// Arusha and Moshi: both in the region the engine calls Tanzania_Northern.
const _arusha = NavPoint(latitude: -3.3869, longitude: 36.6830, name: 'Arusha');
const _moshi = NavPoint(latitude: -3.3349, longitude: 37.3404, name: 'Moshi');
// Zanzibar airport and Stone Town: both on Unguja, in the smallest region of Tanzania (19 MB).
const _zanzibarAirport = NavPoint(latitude: -6.2220, longitude: 39.2249, name: 'Zanzibar airport');
const _stoneTown = NavPoint(latitude: -6.1659, longitude: 39.1912, name: 'Stone Town');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<NavigationResult?> runPage(
    WidgetTester tester,
    NavPoint start,
    NavPoint destination, {
    required bool askBeforeDownload,
    required bool Function() stop,
    required Future<void> Function() onStopped,
  }) async {
    final done = Completer<NavigationResult?>();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<NavigationResult>(MaterialPageRoute(
                  builder: (_) => OfflineNavigationPage(
                    start: start,
                    destination: destination,
                    // The default policy, MapPolicy.autoDownloadCountry.
                    options: NavOptions(simulateRoute: true, voiceGuidance: false, askBeforeDownload: askBeforeDownload),
                  ),
                ));
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
    for (var i = 0; i < 12000 && !done.isCompleted && !stop(); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (!done.isCompleted) {
      debugPrint('page shows: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().join(' | ')}');
      await tester.pump(const Duration(seconds: 1));
      await onStopped();
    }
    return done.isCompleted ? done.future : null;
  }

  group('map areas, no network', () {
    testWidgets('a point in Arusha is in a region of Tanzania, not all of Tanzania', (tester) async {
      final area = await OfflineNavigation.mapAreaAt(_arusha.latitude, _arusha.longitude);
      debugPrint('mapAreaAt(Arusha) = $area');
      expect(area, isNotNull);
      expect(area!.id, 'Tanzania_Northern');
      expect(area.name, isNotEmpty);
      // The whole country is 585 MB (data version 260111); this region is about 105 MB.
      expect(area.sizeBytes, inInclusiveRange(50 * 1000 * 1000, 200 * 1000 * 1000));
      expect(area.isDownloaded, isFalse);
    });

    testWidgets('the two ends of Arusha to Moshi are one area', (tester) async {
      final moshi = await OfflineNavigation.mapAreaAt(_moshi.latitude, _moshi.longitude);
      expect(moshi?.id, 'Tanzania_Northern');
    });

    testWidgets('open sea is no area', (tester) async {
      expect(await OfflineNavigation.mapAreaAt(0, 0), isNull);
    });

    testWidgets('an id the engine does not know is handled, not fatal', (tester) async {
      // The engine aborts the process for an unknown id; every call that takes an id must check it first.
      expect(await OfflineNavigation.mapArea('No_Such_Place'), isNull);
      expect(await NavChannel.getCountryStatus('No_Such_Place'), 0);
      await NavChannel.startDownload(['No_Such_Place']);
      await NavChannel.cancelDownload(['No_Such_Place']);
      await expectLater(
        OfflineNavigation.downloadMapArea('No_Such_Place'),
        throwsA(isA<MapInstallException>().having((e) => e.error, 'error', MapInstallError.invalidId)),
      );
    });

    testWidgets('planDownload lists what the trip needs and downloads nothing', (tester) async {
      final plan = await OfflineNavigation.planDownload(start: _arusha, destination: _moshi);
      debugPrint('plan: $plan');
      expect(plan.areas.map((a) => a.id), ['Tanzania_Northern']);
      expect(plan.baseMapsBytes, greaterThan(50 * 1000 * 1000));
      expect(plan.totalBytes, plan.areas.single.sizeBytes + plan.baseMapsBytes);

      final withoutBase =
          await OfflineNavigation.planDownload(start: _arusha, destination: _moshi, includeBaseMaps: false);
      expect(withoutBase.baseMapsBytes, 0);

      // Still nothing on the device.
      expect((await OfflineNavigation.mapAreaAt(_arusha.latitude, _arusha.longitude))!.isDownloaded, isFalse);
      expect(await OfflineNavigation.baseMapsBytesMissing, greaterThan(0));
    });

    testWidgets('askBeforeDownload shows the areas and sizes, and Cancel downloads nothing', (tester) async {
      final plan = await OfflineNavigation.planDownload(start: _arusha, destination: _moshi);
      final area = plan.areas.single;

      final result = await runPage(
        tester,
        _arusha,
        _moshi,
        askBeforeDownload: true,
        stop: () => find.text('Download offline maps?').evaluate().isNotEmpty,
        onStopped: () async {
          final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().toList();
          debugPrint('confirm panel: ${texts.join(' | ')}');
          expect(texts, contains(area.name));
          expect(texts, contains(formatMapSize(area.sizeBytes)));
          expect(texts, contains('World base map (first run)'));
          expect(texts, contains('Total'));
          expect(texts, contains(formatMapSize(plan.totalBytes)));
          expect(find.text('Download'), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await tester.pump(const Duration(seconds: 1));
        },
      );
      expect(result?.outcome, NavigationOutcome.cancelledByUser, reason: 'page result: $result');

      // Nothing was downloaded or started.
      expect((await OfflineNavigation.mapArea(area.id))!.isDownloaded, isFalse);
      expect(await NavChannel.getCountryStatus(area.id), 7, reason: 'still just downloadable');
      expect(await OfflineNavigation.baseMapsBytesMissing, greaterThan(0));
    });
  });

  group('map areas, network', () {
    testWidgets('asking how much of the base map is missing does not stop its download', (tester) async {
      await OfflineNavigation.initialize();
      expect(await OfflineNavigation.baseMapsBytesMissing, greaterThan(0), reason: 'needs a device without them');

      // The page, or an app showing "72 MB missing", asks while the download runs. Before the fix the engine's
      // query dropped the download in progress and nothing ever finished.
      var asked = 0;
      final poller = Timer.periodic(const Duration(milliseconds: 300), (_) async {
        asked++;
        await OfflineNavigation.baseMapsBytesMissing;
      });
      try {
        await OfflineNavigation.ensureBaseMaps(onProgress: (p) => debugPrint('base maps $p%'))
            .timeout(const Duration(minutes: 8));
      } finally {
        poller.cancel();
      }
      debugPrint('asked $asked times while it downloaded');
      expect(asked, greaterThan(3));
      expect(await OfflineNavigation.baseMapsBytesMissing, 0);
    }, skip: _network != 'base', timeout: const Timeout(Duration(minutes: 12)));

    testWidgets('downloadMapArea downloads one region ahead of time', (tester) async {
      // The smallest region of Tanzania.
      final area = await OfflineNavigation.mapAreaAt(_zanzibarAirport.latitude, _zanzibarAirport.longitude);
      debugPrint('Zanzibar is in $area');
      expect(area, isNotNull);
      expect(area!.isDownloaded, isFalse);
      expect(area.sizeBytes, lessThan(60 * 1000 * 1000), reason: 'a region, not the country');

      final progress = <MapInstallProgress>[];
      await OfflineNavigation.downloadMapArea(area.id, onProgress: progress.add)
          .timeout(const Duration(minutes: 8));

      expect((await OfflineNavigation.mapArea(area.id))!.isDownloaded, isTrue);
      expect(progress, isNotEmpty);
      expect(progress.last.bytesReceived, area.sizeBytes);
      expect(progress.last.fraction, 1.0);
      // Downloaded: a plan for a trip inside it has nothing left of it.
      final plan = await OfflineNavigation.planDownload(
          start: _zanzibarAirport, destination: _stoneTown, includeBaseMaps: false);
      expect(plan.isEmpty, isTrue);
      // And asking again is not an error.
      await OfflineNavigation.downloadMapArea(area.id);

      // A second download is cancellable and leaves the engine usable.
      final token = MapInstallCancelToken()..cancel();
      await expectLater(
        OfflineNavigation.downloadMapArea('Tanzania_Western', cancelToken: token),
        throwsA(isA<MapInstallException>().having((e) => e.error, 'error', MapInstallError.cancelled)),
      );
    }, skip: _network != 'area', timeout: const Timeout(Duration(minutes: 12)));

    testWidgets('a trip with askBeforeDownload: ask, confirm, download, route preview', (tester) async {
      final plan = await OfflineNavigation.planDownload(start: _zanzibarAirport, destination: _stoneTown);
      debugPrint('plan: $plan');
      expect(plan.areas, hasLength(1));
      expect(plan.baseMapsBytes, greaterThan(0));
      final area = plan.areas.single;

      var confirmed = false;
      String? previewTexts;
      final result = await runPage(
        tester,
        _zanzibarAirport,
        _stoneTown,
        askBeforeDownload: true,
        stop: () {
          if (!confirmed && find.text('Download offline maps?').evaluate().isNotEmpty) return true;
          return find.text('Start navigation').evaluate().isNotEmpty;
        },
        onStopped: () async {
          if (find.text('Download offline maps?').evaluate().isNotEmpty) {
            expect(find.text(area.name), findsOneWidget);
            confirmed = true;
            await tester.tap(find.text('Download'));
            // On to the progress screen, the download and the route.
            for (var i = 0; i < 12000 && find.text('Start navigation').evaluate().isEmpty; i++) {
              await tester.pump(const Duration(milliseconds: 100));
              if (i % 100 == 0) {
                debugPrint('page shows: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().join(' | ')}');
              }
            }
          }
          previewTexts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().join(' | ');
          debugPrint('route preview: $previewTexts');
          expect(find.text('Start navigation'), findsOneWidget);
          await tester.tap(find.byIcon(Icons.close));
          await tester.pump(const Duration(seconds: 1));
        },
      );
      expect(result?.outcome, NavigationOutcome.cancelledByUser, reason: 'page result: $result');
      expect(confirmed, isTrue);
      expect(RegExp(r'\d+([.,]\d+)? ?(km|m)\b').hasMatch(previewTexts!), isTrue, reason: previewTexts);
      expect((await OfflineNavigation.mapArea(area.id))!.isDownloaded, isTrue);
      expect(await OfflineNavigation.baseMapsBytesMissing, 0);
      // The second time round nothing needs asking.
      expect((await OfflineNavigation.planDownload(start: _zanzibarAirport, destination: _stoneTown)).isEmpty, isTrue);
    }, skip: _network != 'page', timeout: const Timeout(Duration(minutes: 20)));
  });
}
