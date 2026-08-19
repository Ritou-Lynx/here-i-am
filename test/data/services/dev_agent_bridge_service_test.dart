import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/dev_agent_bridge_service.dart';
import 'package:memex/domain/models/dev_agent_codex_options.dart';

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

  group('Project Memory Bridge discovery', () {
    test('debug loopback remains available without saved Dev Room projects',
        () {
      expect(
        DevAgentBridgeService.projectMemoryBridgeUrlsForTesting(
          const [],
          includeDebugLoopback: true,
        ),
        {'http://127.0.0.1:47831'},
      );
    });

    test('release discovery uses only configured unique URLs', () {
      expect(
        DevAgentBridgeService.projectMemoryBridgeUrlsForTesting(
          const [
            ' https://host.example.invalid ',
            'https://host.example.invalid',
            '',
          ],
          includeDebugLoopback: false,
        ),
        {'https://host.example.invalid'},
      );
    });
  });

  group('Dev Room agent option payload', () {
    test('Codex includes structured controls', () {
      expect(
        DevAgentBridgeService.agentOptionsPayloadForTesting(
          agentType: DevAgentType.codex,
          model: 'gpt-5.6-terra',
          codexOptions: const DevAgentCodexOptions(
            model: 'gpt-5.6-terra',
            reasoningEffort: 'high',
            serviceTier: 'fast',
            verbosity: 'low',
          ),
        ),
        {
          'model': 'gpt-5.6-terra',
          'codex_options': {
            'model': 'gpt-5.6-terra',
            'reasoning_effort': 'high',
            'service_tier': 'fast',
            'verbosity': 'low',
          },
        },
      );
    });

    test('OpenCode never receives Codex controls', () {
      expect(
        DevAgentBridgeService.agentOptionsPayloadForTesting(
          agentType: DevAgentType.opencode,
          model: 'provider/model',
          codexOptions: DevAgentCodexOptions.deep,
        ),
        {'model': 'provider/model'},
      );
    });
  });
}
