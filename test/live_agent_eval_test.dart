import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:memex/agent/companion_agent/companion_agent.dart';
import 'package:memex/data/services/agent_activity_service.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('Live Agent Evaluation', () {
    test('companion live smoke runs only with explicit environment opt-in',
        () async {
      if (Platform.environment['MEMEX_RUN_LIVE_AGENT_SMOKE'] != 'true') {
        return;
      }

      final baseUrl = Platform.environment['OPENAI_BASE_URL'] ?? '';
      final apiKey = Platform.environment['OPENAI_API_KEY'] ?? '';
      if (baseUrl.isEmpty || apiKey.isEmpty) {
        return;
      }

      SharedPreferences.setMockInitialValues({});
      await UserStorage.initL10n();

      const userId = 'agent_eval_user';
      await UserStorage.saveUser(userId);
      AgentActivityService.setInstance(LocalAgentActivityService.instance);

      final llmConfig = LLMConfig(
        key: LLMConfig.defaultClientKey,
        type: LLMConfig.typeChatCompletion,
        modelId: 'anthropic/claude-opus-4.7',
        apiKey: apiKey,
        baseUrl: baseUrl,
        maxTokens: 4096,
        extra: const {},
      );
      await UserStorage.saveLLMConfigs([llmConfig]);

      final tempRoot =
          await Directory.systemTemp.createTemp('memex_agent_eval_');
      await FileSystemService.init(tempRoot.path);
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final character = await CharacterService.instance.createCharacter(
        userId: userId,
        characterData: {
          'name': 'Luna',
          'tags': ['companion', 'warm', 'direct'],
          'persona': 'Natural, concise, empathetic. Avoid lecturing.',
          'enabled': true,
        },
      );
      final chatResources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.companionAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );

      final chunks = <String>[];
      await for (final chunk in CompanionAgent.chat(
        client: chatResources.client,
        modelConfig: chatResources.modelConfig,
        userId: userId,
        characterId: character.id,
        userMessage: 'I am overwhelmed and tired tonight.',
        debugErrorOutput: true,
      )) {
        chunks.add(chunk);
      }

      final response = chunks.join().trim();
      expect(response, isNotEmpty);
      expect(response, isNot(contains('Connection interrupted')));
      expect(response.length, lessThan(1200));
    }, timeout: const Timeout(Duration(minutes: 8)));
  });
}
