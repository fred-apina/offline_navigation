import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigation/offline_navigation.dart';
import 'package:offline_navigation/src/messages.g.dart' show WireMapArea;
import 'package:offline_navigation/src/models.dart' show MapStatus;

void main() {
  group('MapArea.fromWire', () {
    WireMapArea wire(int status) =>
        WireMapArea(id: 'Tanzania_Northern', name: 'Northern', sizeBytes: 104644288, status: status);

    test('a map on the device is downloaded', () {
      expect(MapArea.fromWire(wire(MapStatus.done)).isDownloaded, isTrue);
      expect(MapArea.fromWire(wire(MapStatus.updatable)).isDownloaded, isTrue);
    });

    test('everything else is not', () {
      for (final status in [
        MapStatus.unknown,
        MapStatus.inProgress,
        MapStatus.enqueued,
        MapStatus.failed,
        MapStatus.downloadable,
        MapStatus.partly,
      ]) {
        expect(MapArea.fromWire(wire(status)).isDownloaded, isFalse, reason: 'status $status');
      }
    });

    test('carries the id, name and size', () {
      final area = MapArea.fromWire(wire(MapStatus.downloadable));
      expect(area.id, 'Tanzania_Northern');
      expect(area.name, 'Northern');
      expect(area.sizeBytes, 104644288);
    });
  });

  group('MapDownloadPlan', () {
    const northern = MapArea(id: 'Tanzania_Northern', name: 'Northern', sizeBytes: 104644288, isDownloaded: false);
    const coastal = MapArea(id: 'Tanzania_Coastal', name: 'Coastal', sizeBytes: 122973161, isDownloaded: false);

    test('the total is the areas plus the base maps', () {
      const plan = MapDownloadPlan(areas: [northern, coastal], baseMapsBytes: 72281461);
      expect(plan.totalBytes, 104644288 + 122973161 + 72281461);
      expect(plan.isEmpty, isFalse);
    });

    test('base maps are optional', () {
      const plan = MapDownloadPlan(areas: [northern]);
      expect(plan.baseMapsBytes, 0);
      expect(plan.totalBytes, 104644288);
    });

    test('is empty when there is nothing to download', () {
      expect(const MapDownloadPlan(areas: []).isEmpty, isTrue);
      expect(const MapDownloadPlan(areas: [], baseMapsBytes: 1).isEmpty, isFalse);
      expect(const MapDownloadPlan(areas: [northern]).isEmpty, isFalse);
    });
  });

  group('formatMapSize', () {
    test('uses decimal megabytes, the way the map server lists them', () {
      expect(formatMapSize(104644288), '105 MB');
      expect(formatMapSize(18633163), '19 MB');
      expect(formatMapSize(72281461), '72 MB');
      expect(formatMapSize(2149600), '2.1 MB');
      expect(formatMapSize(585000000), '585 MB');
    });

    test('switches to gigabytes from 1000 MB', () {
      expect(formatMapSize(1234000000), '1.2 GB');
      expect(formatMapSize(999000000), '999 MB');
    });

    test('small and empty sizes', () {
      expect(formatMapSize(0), '0 MB');
      expect(formatMapSize(-5), '0 MB');
      expect(formatMapSize(400000), '<1 MB');
    });
  });

  test('NavOptions asks nothing by default', () {
    expect(const NavOptions().askBeforeDownload, isFalse);
    expect(const NavOptions(askBeforeDownload: true).askBeforeDownload, isTrue);
  });
}
