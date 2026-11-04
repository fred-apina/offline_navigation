import 'dart:async';
import 'dart:io';

import 'region_maps.dart';

/// Creates the HTTP client used for downloads. Overridable for tests.
typedef HttpClientFactory = HttpClient Function();

/// Downloads [url] into [partFile], resuming a partial file from a previous
/// attempt with an HTTP `Range` request when the server supports it.
///
/// On success [partFile] holds the complete file. On failure or cancellation a
/// partial file is kept so the next attempt resumes it, except when it can be
/// told to be corrupt (too large, or the server and the file disagree), in
/// which case it is deleted.
///
/// Throws [MapInstallException] with [MapInstallError.downloadFailed] or
/// [MapInstallError.cancelled].
Future<void> downloadMapFile({
  required Uri url,
  required File partFile,
  Map<String, String> headers = const {},
  int? expectedSize,
  void Function(int received, int? total)? onProgress,
  MapInstallCancelToken? cancelToken,
  Duration connectTimeout = const Duration(seconds: 20),
  Duration idleTimeout = const Duration(seconds: 30),
  HttpClientFactory? clientFactory,
}) async {
  var allowResume = true;
  // At most one restart from scratch: when the server rejects or mis-answers
  // the resume request.
  for (var attempt = 0; attempt < 2; attempt++) {
    final restart = await _attempt(
      url: url,
      partFile: partFile,
      headers: headers,
      expectedSize: expectedSize,
      onProgress: onProgress,
      cancelToken: cancelToken,
      connectTimeout: connectTimeout,
      idleTimeout: idleTimeout,
      clientFactory: clientFactory,
      resume: allowResume,
    );
    if (!restart) return;
    allowResume = false;
  }
  throw const MapInstallException(
      MapInstallError.downloadFailed, 'The server could not resume or restart the download');
}

/// Returns true when the download must be restarted from scratch.
Future<bool> _attempt({
  required Uri url,
  required File partFile,
  required Map<String, String> headers,
  required int? expectedSize,
  required void Function(int received, int? total)? onProgress,
  required MapInstallCancelToken? cancelToken,
  required Duration connectTimeout,
  required Duration idleTimeout,
  required HttpClientFactory? clientFactory,
  required bool resume,
}) async {
  _throwIfCancelled(cancelToken);

  if (!resume && partFile.existsSync()) partFile.deleteSync();
  var existing = partFile.existsSync() ? partFile.lengthSync() : 0;
  if (expectedSize != null && existing > expectedSize) {
    partFile.deleteSync(); // cannot be a prefix of the expected file
    existing = 0;
  }
  if (expectedSize != null && existing == expectedSize) {
    onProgress?.call(existing, expectedSize);
    return false; // already complete
  }

  final client = (clientFactory?.call() ?? HttpClient())
    ..connectionTimeout = connectTimeout
    ..autoUncompress = false;
  void abort() => client.close(force: true);
  cancelToken?.addListener(abort);

  RandomAccessFile? output;
  try {
    final request = await client.getUrl(url).timeout(idleTimeout);
    // Identity encoding keeps Content-Length equal to the bytes on disk.
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    headers.forEach(request.headers.set);
    if (existing > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');

    final response = await request.close().timeout(idleTimeout);
    final status = response.statusCode;

    var append = false;
    int? total = expectedSize;
    switch (status) {
      case HttpStatus.ok:
        // Either a first download, or the server ignored the Range header.
        existing = 0;
        if (response.contentLength >= 0) total = response.contentLength;
      case HttpStatus.partialContent:
        final range = _parseContentRange(response.headers.value(HttpHeaders.contentRangeHeader));
        if (existing == 0 || range == null || range.start != existing) {
          await response.drain<void>();
          return true; // inconsistent resume: start over
        }
        append = true;
        total = range.total ?? (response.contentLength >= 0 ? existing + response.contentLength : total);
      case HttpStatus.requestedRangeNotSatisfiable:
        await response.drain<void>();
        return true; // the partial file does not fit the remote file any more
      default:
        await response.drain<void>();
        throw MapInstallException(MapInstallError.downloadFailed, 'The server answered HTTP $status');
    }
    if (expectedSize != null && total != null && total != expectedSize) {
      throw MapInstallException(MapInstallError.downloadFailed,
          'The server reports $total bytes but $expectedSize were expected');
    }

    output = await partFile.open(mode: append ? FileMode.append : FileMode.write);
    var received = existing;
    onProgress?.call(received, total);
    final clock = Stopwatch()..start();
    var lastReport = Duration.zero;

    await for (final chunk in response.timeout(idleTimeout)) {
      await output.writeFrom(chunk);
      received += chunk.length;
      if (onProgress != null && clock.elapsed - lastReport >= const Duration(milliseconds: 100)) {
        lastReport = clock.elapsed;
        onProgress(received, total);
      }
    }
    await output.close();
    output = null;
    onProgress?.call(received, total);

    final length = partFile.lengthSync();
    final wanted = expectedSize ?? total;
    if (wanted != null && length > wanted) {
      partFile.deleteSync();
      throw MapInstallException(
          MapInstallError.downloadFailed, 'Received $length bytes, expected $wanted');
    }
    if (wanted != null && length < wanted) {
      throw MapInstallException(MapInstallError.downloadFailed,
          'The connection closed after $length of $wanted bytes; retry to resume');
    }
    return false;
  } on MapInstallException {
    rethrow;
  } catch (e) {
    if (cancelToken?.isCancelled ?? false) {
      throw const MapInstallException(MapInstallError.cancelled, 'The download was cancelled');
    }
    throw MapInstallException(MapInstallError.downloadFailed, _describe(e));
  } finally {
    cancelToken?.removeListener(abort);
    try {
      await output?.close();
    } catch (_) {}
    client.close(force: true);
  }
}

void _throwIfCancelled(MapInstallCancelToken? token) {
  if (token?.isCancelled ?? false) {
    throw const MapInstallException(MapInstallError.cancelled, 'The download was cancelled');
  }
}

String _describe(Object e) => switch (e) {
      TimeoutException() => 'The connection timed out',
      SocketException(:final message) => 'Network error: $message',
      HttpException(:final message) => 'HTTP error: $message',
      TlsException(:final message) => 'TLS error: $message',
      _ => 'Download failed: $e',
    };

({int start, int? total})? _parseContentRange(String? value) {
  if (value == null) return null;
  final match = RegExp(r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$').firstMatch(value.trim());
  if (match == null) return null;
  return (start: int.parse(match.group(1)!), total: match.group(3) == '*' ? null : int.parse(match.group(3)!));
}
