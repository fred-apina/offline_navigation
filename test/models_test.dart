import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigation/src/models.dart';

void main() {
  group('CarTurn.fromOrdinal', () {
    test('maps valid ordinals to engine turn kinds', () {
      expect(CarTurn.fromOrdinal(0), CarTurn.noTurn);
      expect(CarTurn.fromOrdinal(1), CarTurn.goStraight);
      expect(CarTurn.fromOrdinal(14), CarTurn.reachedYourDestination);
    });

    test('falls back to noTurn for null and out-of-range', () {
      expect(CarTurn.fromOrdinal(null), CarTurn.noTurn);
      expect(CarTurn.fromOrdinal(-1), CarTurn.noTurn);
      expect(CarTurn.fromOrdinal(999), CarTurn.noTurn);
    });
  });

  group('GuidanceUpdate.fromMap', () {
    test('parses a complete event', () {
      final update = GuidanceUpdate.fromMap(const {
        'distToTarget': '4.2',
        'distToTargetUnits': 'Kilometers',
        'distToTurn': '300',
        'distToTurnUnits': 'Meters',
        'nextStreet': 'Bahnhofstrasse',
        'currentStreet': 'Rämistrasse',
        'timeSeconds': 201,
        'completionPercent': 37.5,
        'carDirection': 2,
        'exitNum': 3,
      });
      expect(update.distanceToTargetText, '4.2 km');
      expect(update.distanceToTurnText, '300 m');
      expect(update.nextStreet, 'Bahnhofstrasse');
      expect(update.currentStreet, 'Rämistrasse');
      expect(update.timeRemaining, const Duration(seconds: 201));
      expect(update.completionPercent, 37.5);
      expect(update.turn, CarTurn.turnRight);
      expect(update.roundaboutExit, 3);
    });

    test('tolerates missing and empty fields', () {
      final update = GuidanceUpdate.fromMap(const {});
      expect(update.distanceToTargetText, '');
      expect(update.distanceToTurnText, '');
      expect(update.nextStreet, '');
      expect(update.timeRemaining, Duration.zero);
      expect(update.completionPercent, 0);
      expect(update.turn, CarTurn.noTurn);
    });

    test('imperial units get the right suffix', () {
      final update = GuidanceUpdate.fromMap(const {
        'distToTarget': '2.5',
        'distToTargetUnits': 'Miles',
        'distToTurn': '500',
        'distToTurnUnits': 'Feet',
      });
      expect(update.distanceToTargetText, '2.5 mi');
      expect(update.distanceToTurnText, '500 ft');
    });
  });

  group('MapDownloadEvent.fromMap', () {
    test('parses a progress event', () {
      final event = MapDownloadEvent.fromMap(const {
        'countryId': 'Tanzania',
        'status': 1,
        'progress': 42,
      });
      expect(event.countryId, 'Tanzania');
      expect(event.status, MapStatus.inProgress);
      expect(event.progress, 42);
    });

    test('defaults for missing fields', () {
      final event = MapDownloadEvent.fromMap(const {});
      expect(event.countryId, '');
      expect(event.status, MapStatus.unknown);
      expect(event.progress, 0);
    });
  });

  group('MapStatus', () {
    test('isDownloaded covers done and updatable only', () {
      expect(MapStatus.isDownloaded(MapStatus.done), isTrue);
      expect(MapStatus.isDownloaded(MapStatus.updatable), isTrue);
      expect(MapStatus.isDownloaded(MapStatus.inProgress), isFalse);
      expect(MapStatus.isDownloaded(MapStatus.failed), isFalse);
      expect(MapStatus.isDownloaded(MapStatus.downloadable), isFalse);
    });

    test('isActive covers the three transfer states', () {
      expect(MapStatus.isActive(MapStatus.inProgress), isTrue);
      expect(MapStatus.isActive(MapStatus.applying), isTrue);
      expect(MapStatus.isActive(MapStatus.enqueued), isTrue);
      expect(MapStatus.isActive(MapStatus.done), isFalse);
    });
  });

  group('NavPoint', () {
    test('rejects out-of-range coordinates', () {
      expect(() => NavPoint(latitude: 91, longitude: 0), throwsAssertionError);
      expect(() => NavPoint(latitude: 0, longitude: 181), throwsAssertionError);
    });

    test('accepts boundary coordinates', () {
      expect(const NavPoint(latitude: 90, longitude: 180), isA<NavPoint>());
      expect(const NavPoint(latitude: -90, longitude: -180), isA<NavPoint>());
    });
  });
}
