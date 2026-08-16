import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/ingestion/safe_http_client.dart';

/// A resolver whose answers can be sequenced: on each lookup of a host it
/// returns the next entry. Simulates a rebinding DNS that would answer
/// differently if the connection layer did a second lookup.
class _RebindingResolver implements DnsResolver {
  final Map<String, List<List<InternetAddress>>> sequences;
  final Map<String, int> lookupCounts = {};

  _RebindingResolver(this.sequences);

  @override
  Future<List<InternetAddress>> lookup(String host) async {
    final seq = sequences[host] ?? const [];
    final idx = (lookupCounts[host] ?? 0);
    lookupCounts[host] = idx + 1;
    return seq.isEmpty ? const [] : seq[idx.clamp(0, seq.length - 1)];
  }
}

class _RecordingConnector {
  final List<({InternetAddress address, int port, String host, bool isSecure})>
      calls = [];

  /// Records the requested (pinned) target, then fails the connect — enough
  /// to prove what address the transport would have used.
  Future<Socket> failConnect({
    required InternetAddress address,
    required int port,
    required String host,
    required bool isSecure,
  }) async {
    calls.add((address: address, port: port, host: host, isSecure: isSecure));
    throw const SocketException('probe: connect target recorded');
  }
}

/// Connects to a local test server (loopback) while recording the target it
/// was asked to connect to. The "remote" address is never really dialed, so
/// tests can run the full HTTP flow over real sockets without network.
class _LocalServerConnector {
  final int serverPort;
  final List<({InternetAddress address, int port, String host, bool isSecure})>
      calls = [];

  _LocalServerConnector(this.serverPort);

  Future<Socket> call({
    required InternetAddress address,
    required int port,
    required String host,
    required bool isSecure,
  }) async {
    calls.add((address: address, port: port, host: host, isSecure: isSecure));
    // Real TCP connection — but to the local test server, not the address
    // that was pinned. TLS is skipped by design (the test server is plain
    // HTTP); the pin assertion lives in [calls].
    return Socket.connect(InternetAddress.loopbackIPv4, serverPort);
  }
}

void main() {
  group('DNS rebinding — connection pinning', () {
    test('connects to the exact validated address (single resolution)',
        () async {
      final resolver = _RebindingResolver({
        'public.example': [
          [InternetAddress('93.184.216.34')],
          [InternetAddress('10.0.0.7')], // would be used by a re-lookup
        ],
      });
      final connector = _RecordingConnector();
      final client = SafeHttpClient(
        config: const SafeHttpConfig(maxRetries: 0),
        resolver: resolver,
        connectFn: connector.failConnect,
      );

      final r = await client.fetch('https://public.example/doc');

      // The probe aborts the connect, so the fetch fails — but the failure
      // must be at the transport layer AFTER pinning, never before it.
      expect(r.success, isFalse);

      // Exactly one DNS lookup per host, and the connection was pinned to
      // the address that lookup returned — no re-resolution at connect time.
      expect(resolver.lookupCounts['public.example'], 1);
      expect(connector.calls.length, 1);
      expect(connector.calls.single.address.address, '93.184.216.34');
      expect(connector.calls.single.port, 443);
      expect(connector.calls.single.host, 'public.example');
      expect(connector.calls.single.isSecure, isTrue);
    });

    test('DNS rebinding attack blocked: post-validation answer change cannot '
        'redirect the connection', () async {
      // First answer looks public; any SECOND lookup would return the
      // attacker's internal address. With pinning, no second lookup happens.
      final resolver = _RebindingResolver({
        'victim.example': [
          [InternetAddress('93.184.216.34')],
          [InternetAddress('127.0.0.1')],
          [InternetAddress('169.254.169.254')],
        ],
      });
      final connector = _RecordingConnector();
      final client = SafeHttpClient(
        config: const SafeHttpConfig(maxRetries: 0),
        resolver: resolver,
        connectFn: connector.failConnect,
      );

      await client.fetch('http://victim.example/');

      expect(resolver.lookupCounts['victim.example'], 1);
      expect(connector.calls.length, 1);
      expect(connector.calls.single.address.address, '93.184.216.34');
      expect(connector.calls.single.port, 80);
      // The private/loopback/metadata answers were never even seen by the
      // transport — they never became connect targets.
    });

    test('no validated pin → transport fails closed (no unvalidated connect)',
        () async {
      final connector = _RecordingConnector();
      final client = SafeHttpClient(
        config: const SafeHttpConfig(maxRetries: 0),
        resolver: _RebindingResolver({}), // never resolves anything
        connectFn: connector.failConnect,
      );

      final r = await client.fetch('https://empty.example/');

      expect(r.success, isFalse);
      expect(r.errorMessage, contains('DNS resolution failed'));
      expect(connector.calls, isEmpty);
    });

    test('redirect hops are each re-validated and pinned to their own '
        'verified address (full HTTP flow over real sockets)', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        try {
          if (request.uri.path == '/old') {
            request.response.statusCode = 302;
            request.response.headers
                .set('location', 'https://target.example/new');
            request.response.close();
            return;
          }
          request.response.headers.contentType = ContentType.html;
          request.response
              .write('<html><body><h1>Pinned OK</h1></body></html>');
          request.response.close();
        } catch (_) {
          // Client may destroy the socket early (redirect hop) — ignore.
        }
      });

      final resolver = _RebindingResolver({
        'start.example': [
          [InternetAddress('93.184.216.34')],
          [InternetAddress('127.0.0.1')],
        ],
        'target.example': [
          [InternetAddress('104.26.10.229')],
          [InternetAddress('10.0.0.5')],
        ],
      });
      final connector = _LocalServerConnector(server.port);
      final client = SafeHttpClient(
        config: const SafeHttpConfig(maxRetries: 0),
        resolver: resolver,
        connectFn: connector.call,
      );

      final r = await client.fetch('https://start.example/old');

      expect(r.success, isTrue, reason: r.errorMessage);
      expect(r.finalUrl, 'https://target.example/new');
      expect(r.body, contains('Pinned OK'));

      // Hop 1: start.example pinned to its validated address.
      // Hop 2: target.example resolved + validated + pinned separately.
      expect(connector.calls.length, 2);
      expect(connector.calls[0].host, 'start.example');
      expect(connector.calls[0].address.address, '93.184.216.34');
      expect(connector.calls[1].host, 'target.example');
      expect(connector.calls[1].address.address, '104.26.10.229');
      // Each host resolved exactly once — the rebinding answers never used.
      expect(resolver.lookupCounts['start.example'], 1);
      expect(resolver.lookupCounts['target.example'], 1);
    });
  });
}
