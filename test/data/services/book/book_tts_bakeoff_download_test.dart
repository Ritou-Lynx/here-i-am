import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/book/book_tts_bakeoff_service.dart';

void main() {
  test('resumes an interrupted download from the last received byte', () async {
    final bytes =
        Uint8List.fromList(List<int>.generate(200000, (i) => i % 251));
    var droppedFirstRequest = false;
    final server = await _serve((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (!droppedFirstRequest && range == null) {
        droppedFirstRequest = true;
        return _dropAfter(request, bytes, 120000);
      }
      return _serveRange(request, bytes);
    });
    final dir = await Directory.systemTemp.createTemp('bakeoff_download');
    final target = File('${dir.path}/model.part.tar.bz2');
    addTearDown(() => _cleanup(server, dir, target));

    final service = BookTtsBakeoffService(
      supportDirectory: dir,
      retryDelay: Duration.zero,
    );
    final progresses = <double>[];
    await service.downloadTo(serverUrl(server), target, onProgress: progresses.add);

    expect(await target.length(), bytes.length);
    expect(await target.readAsBytes(), bytes);
    // The retry resumed from a non-zero offset; progress must not restart at 0.
    expect(progresses.first, greaterThan(0));
    expect(progresses.last, 1.0);
  });

  test('keeps the partial file when every attempt is interrupted', () async {
    final bytes =
        Uint8List.fromList(List<int>.generate(100000, (i) => i % 251));
    final server = await _serve(
        (request) => _dropAfter(request, bytes, 40000));
    final dir = await Directory.systemTemp.createTemp('bakeoff_download');
    final target = File('${dir.path}/model.part.tar.bz2');
    addTearDown(() => _cleanup(server, dir, target));

    final service = BookTtsBakeoffService(
      supportDirectory: dir,
      retryDelay: Duration.zero,
    );

    await expectLater(
      service.downloadTo(serverUrl(server), target, onProgress: (_) {}),
      throwsA(anything),
    );

    // The partial bytes survive so a later attempt can resume.
    expect(await target.exists(), isTrue);
    final partialLength = await target.length();
    expect(partialLength, greaterThan(0));
    expect(partialLength, lessThan(bytes.length));
  });

  test('downloads cleanly without a Range-capable server', () async {
    final bytes =
        Uint8List.fromList(List<int>.generate(50000, (i) => (i * 7) % 256));
    final server = await _serve(
        (request) => _serveRange(request, bytes, ignoreRange: true));
    final dir = await Directory.systemTemp.createTemp('bakeoff_download');
    final target = File('${dir.path}/model.part.tar.bz2');
    addTearDown(() => _cleanup(server, dir, target));

    final service = BookTtsBakeoffService(
      supportDirectory: dir,
      retryDelay: Duration.zero,
    );
    await service.downloadTo(serverUrl(server), target, onProgress: (_) {});

    expect(await target.length(), bytes.length);
    expect(await target.readAsBytes(), bytes);
  });
}

Future<HttpServer> _serve(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      await handler(request);
    } catch (_) {
      // Abrupt client-side disconnects also surface server-side; ignore.
    }
  });
  return server;
}

Uri serverUrl(HttpServer server) =>
    Uri.parse('http://${server.address.address}:${server.port}/');

Future<void> _cleanup(HttpServer server, Directory dir, File target) async {
  try {
    await server.close(force: true);
  } catch (_) {}
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      if (await target.exists()) await target.delete();
      if (await dir.exists()) await dir.delete(recursive: true);
      return;
    } catch (_) {
      // Windows may briefly keep a handle on an aborted connection's file.
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }
}

Future<void> _serveRange(
  HttpRequest request,
  Uint8List bytes, {
  bool ignoreRange = false,
}) async {
  var start = 0;
  final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
  if (!ignoreRange && rangeHeader != null && rangeHeader.startsWith('bytes=')) {
    final parsed = int.tryParse(rangeHeader.substring(6).split('-').first);
    if (parsed != null && parsed > 0 && parsed < bytes.length) start = parsed;
  }
  final response = request.response;
  response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
  if (start > 0) {
    response.statusCode = HttpStatus.partialContent;
    response.headers.set(HttpHeaders.contentRangeHeader,
        'bytes $start-${bytes.length - 1}/${bytes.length}');
    response.contentLength = bytes.length - start;
    response.add(Uint8List.sublistView(bytes, start));
  } else {
    response.statusCode = HttpStatus.ok;
    response.contentLength = bytes.length;
    response.add(bytes);
  }
  await response.close();
}

/// Declares the full [bytes.length] but writes only [count] bytes, so the
/// connection is torn down short of the promised body — a mid-transfer drop.
Future<void> _dropAfter(
  HttpRequest request,
  Uint8List bytes,
  int count,
) async {
  final response = request.response;
  response.statusCode = HttpStatus.ok;
  response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
  response.contentLength = bytes.length;
  response.add(Uint8List.sublistView(bytes, 0, count));
  await response.flush();
  try {
    await response.close();
  } catch (_) {
    // The body is shorter than its declared length; dart:io closes the socket,
    // which is exactly the dropped connection we want to simulate.
  }
}
