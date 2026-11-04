import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigation/offline_navigation.dart';
import 'package:offline_navigation/src/region_map_download.dart';

/// A tiny HTTP server serving [body] with configurable behaviour.
class _Server {
  _Server(this.body);

  final Uint8List body;
  late final HttpServer _server;

  /// When false the server ignores Range headers and always answers 200.
  bool supportRange = true;

  /// Answer this status instead of serving the file.
  int? forceStatus;

  /// Close the connection after this many bytes (simulates a drop).
  int? dropAfter;

  /// Send this many bytes, then stall without closing (simulates a dead link).
  int? stallAfter;

  /// Number of requests and the Range header of each.
  final List<String?> ranges = [];

  final Completer<void> _stopped = Completer<void>();

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}/map.mwm');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      final response = request.response;
      if (forceStatus != null) {
        response.statusCode = forceStatus!;
        await response.close();
        return;
      }
      var start = 0;
      if (supportRange && range != null) {
        start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        if (start >= body.length) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await response.close();
          return;
        }
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(HttpHeaders.contentRangeHeader,
            'bytes $start-${body.length - 1}/${body.length}');
      }
      final chunk = body.sublist(start);
      final cutoff = dropAfter ?? stallAfter;
      if (cutoff != null && cutoff < chunk.length) {
        // Raw HTTP: announce the full length, deliver only part of it.
        final socket = await response.detachSocket(writeHeaders: false);
        final status = start > 0 ? '206 Partial Content' : '200 OK';
        final rangeHeader = start > 0
            ? 'Content-Range: bytes $start-${body.length - 1}/${body.length}\r\n'
            : '';
        socket.write('HTTP/1.1 $status\r\n'
            'Content-Length: ${chunk.length}\r\n'
            '$rangeHeader'
            'Connection: close\r\n\r\n');
        socket.add(chunk.sublist(0, cutoff));
        await socket.flush();
        if (stallAfter != null) await _stopped.future;
        socket.destroy();
        return;
      }
      response.headers.contentLength = chunk.length;
      response.add(chunk);
      await response.close();
    });
  }

  Future<void> stop() {
    if (!_stopped.isCompleted) _stopped.complete();
    return _server.close(force: true);
  }
}

Uint8List _bytes(int n) => Uint8List.fromList(List.generate(n, (i) => (i * 31 + 7) & 0xff));

void main() {
  late Directory dir;
  late File part;
  late _Server server;
  final body = _bytes(300 * 1024);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('region_map_test');
    part = File('${dir.path}/serengeti.mwm.part');
    server = _Server(body);
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    await dir.delete(recursive: true);
  });

  Future<void> download({int? size, MapInstallCancelToken? token, void Function(int, int?)? progress}) =>
      downloadMapFile(
        url: server.url,
        partFile: part,
        expectedSize: size,
        cancelToken: token,
        onProgress: progress,
        idleTimeout: const Duration(seconds: 5),
      );

  Future<MapInstallError?> failureOf(Future<void> Function() action) async {
    try {
      await action();
    } on MapInstallException catch (e) {
      return e.error;
    }
    return null;
  }

  test('downloads a file completely and reports progress up to the total', () async {
    final reports = <(int, int?)>[];
    await download(size: body.length, progress: (r, t) => reports.add((r, t)));
    expect(part.readAsBytesSync(), body);
    expect(reports.last, (body.length, body.length));
  });

  test('works when the size is not known in advance', () async {
    await download();
    expect(part.readAsBytesSync(), body);
  });

  test('resumes a partial file with a Range request and appends the rest', () async {
    part.writeAsBytesSync(body.sublist(0, 100000));
    await download(size: body.length);
    expect(part.readAsBytesSync(), body);
    expect(server.ranges.single, 'bytes=100000-');
  });

  test('starts over when the server ignores Range', () async {
    server.supportRange = false;
    part.writeAsBytesSync(body.sublist(0, 100000));
    await download(size: body.length);
    expect(part.readAsBytesSync(), body, reason: 'no duplicated prefix');
  });

  test('restarts from scratch after 416 on a stale partial file', () async {
    // A partial file as long as the remote file, but not complete data.
    part.writeAsBytesSync(Uint8List(body.length + 5));
    await download(); // size unknown: the server answers 416 for the stale file
    expect(part.readAsBytesSync(), body);
  });

  test('discards a partial file that is longer than the expected size', () async {
    part.writeAsBytesSync(Uint8List(body.length + 10));
    await download(size: body.length);
    expect(part.readAsBytesSync(), body);
  });

  test('treats an already complete partial file as done without a request', () async {
    part.writeAsBytesSync(body);
    await download(size: body.length);
    expect(server.ranges, isEmpty);
  });

  test('HTTP errors become downloadFailed', () async {
    server.forceStatus = 404;
    expect(await failureOf(() => download(size: body.length)), MapInstallError.downloadFailed);
  });

  test('refuses a server whose size disagrees with the expected one', () async {
    expect(await failureOf(() => download(size: body.length + 1)), MapInstallError.downloadFailed);
  });

  test('keeps the partial file when the connection drops, and a retry resumes it', () async {
    server.dropAfter = 120000;
    expect(await failureOf(() => download(size: body.length)), MapInstallError.downloadFailed);
    expect(part.lengthSync(), greaterThan(0));
    expect(part.lengthSync(), lessThan(body.length));

    server.dropAfter = null;
    await download(size: body.length);
    expect(part.readAsBytesSync(), body);
  });

  test('an unreachable server is a download failure, not a crash', () async {
    final deadUrl = server.url;
    await server.stop();
    final error = await failureOf(() => downloadMapFile(
          url: deadUrl,
          partFile: part,
          expectedSize: body.length,
          idleTimeout: const Duration(seconds: 5),
        ));
    expect(error, MapInstallError.downloadFailed);
    server = _Server(body); // keeps tearDown happy
    await server.start();
  });

  test('cancelling before the start throws cancelled and touches nothing', () async {
    final token = MapInstallCancelToken()..cancel();
    expect(await failureOf(() => download(token: token)), MapInstallError.cancelled);
    expect(part.existsSync(), isFalse);
    expect(server.ranges, isEmpty);
  });

  test('cancelling mid-download throws cancelled and keeps the partial file', () async {
    server.stallAfter = 50000;
    final token = MapInstallCancelToken();
    final running = failureOf(() => download(size: body.length, token: token));

    // Like a user pressing "Cancel": wait until data has reached the disk while
    // the link is stalled, then cancel.
    final deadline = DateTime.now().add(const Duration(seconds: 4));
    while (!(part.existsSync() && part.lengthSync() >= 50000)) {
      expect(DateTime.now().isBefore(deadline), isTrue, reason: 'no data arrived');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    token.cancel();

    expect(await running.timeout(const Duration(seconds: 3)), MapInstallError.cancelled,
        reason: 'cancel must abort a stalled connection, not wait for the idle timeout');
    expect(part.lengthSync(), 50000, reason: 'the partial file is kept for resuming');

    // ...and the next attempt continues from there.
    server.stallAfter = null;
    await download(size: body.length);
    expect(part.readAsBytesSync(), body);
    expect(server.ranges.last, 'bytes=50000-');
  });
}
