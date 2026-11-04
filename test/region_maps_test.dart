import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigation/offline_navigation.dart';

void main() {
  const goodHash = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  group('isValidRegionMapId', () {
    test('accepts letters, digits, underscore and dash', () {
      expect(isValidRegionMapId('serengeti'), isTrue);
      expect(isValidRegionMapId('Mikumi_NP-2'), isTrue);
      expect(isValidRegionMapId('a' * 64), isTrue);
    });

    test('rejects everything that could escape the maps directory or break a file name', () {
      for (final id in ['', ' ', 'a b', '../x', 'a/b', r'a\b', 'x.mwm', 'ü', 'a' * 65, 'a\nb']) {
        expect(isValidRegionMapId(id), isFalse, reason: 'id "$id"');
      }
    });
  });

  group('RegionMapSource.validate', () {
    RegionMapSource source({
      String id = 'serengeti',
      String url = 'https://example.com/serengeti.mwm',
      String sha256 = goodHash,
      int? size = 100,
    }) =>
        RegionMapSource(id: id, url: Uri.parse(url), sha256: sha256, sizeBytes: size);

    MapInstallError? errorOf(RegionMapSource s) {
      try {
        s.validate();
      } on MapInstallException catch (e) {
        return e.error;
      }
      return null;
    }

    test('accepts a well-formed source', () => expect(errorOf(source()), isNull));
    test('accepts upper-case hashes', () => expect(errorOf(source(sha256: goodHash.toUpperCase())), isNull));
    test('rejects a bad id', () => expect(errorOf(source(id: '../evil')), MapInstallError.invalidId));
    test('rejects a malformed hash', () {
      expect(errorOf(source(sha256: 'abc')), MapInstallError.other);
      expect(errorOf(source(sha256: 'z' * 64)), MapInstallError.other);
    });
    test('rejects non-http schemes', () {
      expect(errorOf(source(url: 'file:///etc/passwd')), MapInstallError.other);
      expect(errorOf(source(url: 'ftp://example.com/a.mwm')), MapInstallError.other);
    });
    test('rejects a non-positive size', () => expect(errorOf(source(size: 0)), MapInstallError.other));
    test('allows an unknown size', () => expect(errorOf(source(size: null)), isNull));
  });

  group('MapInstallProgress.fraction', () {
    test('is the received share of the total', () {
      expect(const MapInstallProgress(bytesReceived: 25, totalBytes: 100).fraction, 0.25);
    });
    test('is null without a total', () {
      expect(const MapInstallProgress(bytesReceived: 25).fraction, isNull);
    });
    test('never exceeds 1', () {
      expect(const MapInstallProgress(bytesReceived: 150, totalBytes: 100).fraction, 1.0);
    });
  });

  group('MapInstallCancelToken', () {
    test('notifies listeners once and remembers it was cancelled', () {
      final token = MapInstallCancelToken();
      var calls = 0;
      token.addListener(() => calls++);
      token.cancel();
      token.cancel();
      expect(calls, 1);
      expect(token.isCancelled, isTrue);
    });

    test('calls a listener added after cancellation immediately', () {
      final token = MapInstallCancelToken()..cancel();
      var called = false;
      token.addListener(() => called = true);
      expect(called, isTrue);
    });

    test('does not call removed listeners', () {
      final token = MapInstallCancelToken();
      var called = false;
      void listener() => called = true;
      token.addListener(listener);
      token.removeListener(listener);
      token.cancel();
      expect(called, isFalse);
    });
  });

  group('NavigationResult', () {
    test('keeps the original positional constructor working', () {
      const result = NavigationResult(NavigationOutcome.cancelledByUser);
      expect(result.outcome, NavigationOutcome.cancelledByUser);
      expect(result.failure, isNull);
      expect(result.missingMaps, isEmpty);
    });

    test('failed() carries a typed failure and the missing maps', () {
      const result = NavigationResult.failed(
        'x',
        failure: NavigationFailure.mapsMissing,
        missingMaps: ['Tanzania'],
      );
      expect(result.outcome, NavigationOutcome.failed);
      expect(result.failure, NavigationFailure.mapsMissing);
      expect(result.missingMaps, ['Tanzania']);
      expect(result.toString(), contains('mapsMissing'));
    });
  });

  group('NavOptions', () {
    test('downloads country maps by default, as in 0.1.x', () {
      expect(const NavOptions().mapPolicy, MapPolicy.autoDownloadCountry);
    });
  });
}
