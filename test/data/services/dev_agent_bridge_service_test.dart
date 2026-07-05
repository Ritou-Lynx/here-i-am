import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/dev_agent_bridge_service.dart';

void main() {
  group('DevAgentBridgeService.validateBridgeUrlError', () {
    test('accepts HTTPS bridge URLs', () {
      expect(
        DevAgentBridgeService.validateBridgeUrlError(
          'https://host.example.invalid',
        ),
        isNull,
      );
    });

    test('accepts debug loopback HTTP for USB bridge testing', () {
      expect(
        DevAgentBridgeService.validateBridgeUrlError(
          'http://127.0.0.1:47831',
        ),
        isNull,
      );
      expect(
        DevAgentBridgeService.validateBridgeUrlError(
          'http://localhost:47831',
        ),
        isNull,
      );
    });

    test('rejects non-loopback HTTP URLs', () {
      expect(
        DevAgentBridgeService.validateBridgeUrlError(
          'http://192.168.1.20:47831',
        ),
        isNotNull,
      );
    });
  });
}
