import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memex/data/services/home_turbo_tts_service.dart';

Uint8List _wav() {
  final bytes = Uint8List(44);
  bytes.setAll(0, ascii.encode('RIFF'));
  bytes.setAll(8, ascii.encode('WAVE'));
  return bytes;
}

void main() {
  late Map<String, String> kv;
  late List<http.Request> requests;

  void serve(Future<http.Response> Function(http.Request) handler) {
    HomeTurboTtsService.clientFactory = () => MockClient((req) {
          requests.add(req);
          return handler(req);
        });
  }

  setUp(() {
    kv = {'comic.hermes_url': 'http://home-pc.example.ts.net:8790/'};
    requests = [];
    HomeTurboTtsService.kvRead = (key) async => kv[key];
    HomeTurboTtsService.kvWrite = (key, value) async => kv[key] = value;
    HomeTurboTtsService.breaker.reset();
  });

  group('url', () {
    test('derives https 8445 from the comic server url', () async {
      expect(await HomeTurboTtsService.resolveBaseUrl(),
          'https://home-pc.example.ts.net:8445');
    });

    test('saved url wins and is normalized', () async {
      await HomeTurboTtsService.saveUrl(' https://other:9000/ ');
      expect(await HomeTurboTtsService.resolveBaseUrl(), 'https://other:9000');
    });

    test('no url configured means no request', () async {
      kv.clear();
      serve((_) async => http.Response('', 500));
      expect(await HomeTurboTtsService.trySynthesize('Hello there.'), isNull);
      expect(requests, isEmpty);
    });
  });

  group('synthesize', () {
    test('returns wav bytes and sends no token', () async {
      serve((req) async => http.Response.bytes(_wav(), 200,
          headers: {'x-gen-ms': '320', 'x-audio-ms': '900'}));
      final result = await HomeTurboTtsService.synthesize('Hey.');
      expect(result.audio, isNotNull);
      expect(result.genMs, 320);
      expect(result.audioMs, 900);
      final req = requests.single;
      expect(req.url.toString(),
          'https://home-pc.example.ts.net:8445/v1/tts/speak');
      expect(req.headers.containsKey('Authorization'), isFalse);
      expect(jsonDecode(req.body), {'text': 'Hey.'});
    });

    test('server error code is reported', () async {
      serve((_) async => http.Response(jsonEncode({'error': 'busy'}), 503));
      final result = await HomeTurboTtsService.synthesize('Hey.');
      expect(result.audio, isNull);
      expect(result.error, 'http_503:busy');
    });

    test('non-wav body is a failure', () async {
      serve((_) async => http.Response('<html>', 200));
      expect((await HomeTurboTtsService.synthesize('Hey.')).error, 'not_wav');
    });

    test('timeout is a failure', () async {
      serve((_) => Completer<http.Response>().future);
      final result = await HomeTurboTtsService.synthesize('Hey.',
          timeout: const Duration(milliseconds: 20));
      expect(result.error, 'timeout');
    });
  });

  group('trySynthesize', () {
    test('Chinese text is never sent and does not count as failure', () async {
      serve((_) async => http.Response.bytes(_wav(), 200));
      expect(await HomeTurboTtsService.trySynthesize('嗯，我在。'), isNull);
      expect(await HomeTurboTtsService.trySynthesize('OK 好的'), isNull);
      expect(requests, isEmpty);
      expect(HomeTurboTtsService.breaker.consecutiveFailures, 0);
    });

    test('too long text is not sent', () async {
      serve((_) async => http.Response.bytes(_wav(), 200));
      expect(
          await HomeTurboTtsService.trySynthesize(
              'a' * (HomeTurboTtsService.maxChars + 1)),
          isNull);
      expect(requests, isEmpty);
    });

    test('three failures open the breaker', () async {
      serve((_) async => http.Response('', 500));
      for (var i = 0; i < 3; i++) {
        expect(await HomeTurboTtsService.trySynthesize('Hey.'), isNull);
      }
      expect(requests, hasLength(3));
      expect(HomeTurboTtsService.breaker.isOpen, isTrue);
      expect(await HomeTurboTtsService.trySynthesize('Hey.'), isNull);
      expect(requests, hasLength(3));
    });

    test('a success resets the failure count', () async {
      var fail = true;
      serve((_) async =>
          fail ? http.Response('', 500) : http.Response.bytes(_wav(), 200));
      await HomeTurboTtsService.trySynthesize('Hey.');
      await HomeTurboTtsService.trySynthesize('Hey.');
      fail = false;
      expect(await HomeTurboTtsService.trySynthesize('Hey.'), isNotNull);
      expect(HomeTurboTtsService.breaker.consecutiveFailures, 0);
    });
  });

  group('health', () {
    test('usable needs model loaded and caller authorized', () async {
      serve((_) async => http.Response(
          jsonEncode({
            'ok': true,
            'model_loaded': true,
            'caller_authorized': false,
          }),
          200));
      final health = await HomeTurboTtsService.checkHealth();
      expect(health.reachable, isTrue);
      expect(health.usable, isFalse);
      expect(health.summary, contains('放行名单'));
    });

    test('prepareForSession trips the breaker when unusable', () async {
      serve((_) async => http.Response('', 502));
      await HomeTurboTtsService.prepareForSession();
      expect(HomeTurboTtsService.breaker.isOpen, isTrue);
    });

    test('prepareForSession resets the breaker when usable', () async {
      HomeTurboTtsService.breaker.trip();
      serve((_) async => http.Response(
          jsonEncode({'model_loaded': true, 'caller_authorized': true}), 200));
      await HomeTurboTtsService.prepareForSession();
      expect(HomeTurboTtsService.breaker.isOpen, isFalse);
    });
  });

  group('breaker', () {
    test('closes again after the open window', () {
      var now = DateTime(2026, 11, 1, 10);
      final breaker = HomeTurboBreaker(now: () => now);
      breaker.trip();
      expect(breaker.isOpen, isTrue);
      now = now.add(HomeTurboBreaker.openFor + const Duration(seconds: 1));
      expect(breaker.isOpen, isFalse);
      expect(breaker.consecutiveFailures, 0);
    });
  });

  test('timeout grows with text length', () {
    expect(HomeTurboTtsService.timeoutFor('').inMilliseconds, 4000);
    expect(HomeTurboTtsService.timeoutFor('a' * 200).inMilliseconds, 9000);
  });
}
