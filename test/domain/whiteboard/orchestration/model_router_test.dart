import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/domain/whiteboard/orchestration/model_router.dart';

const sampleConfigJson = '''
{
  "schema_version": 1,
  "task_routing": {
    "content_generation": {
      "primary": {"model": "claude-sonnet-4", "quota_key": "anthropic_main"},
      "fallback": {"model": "gemini-pro", "quota_key": "google_main"},
      "local": {"model": "local-llm"}
    },
    "coding": {
      "primary": {"model": "claude-code", "quota_key": "anthropic_main"},
      "fallback": {"model": "codex", "quota_key": "openai_main"}
    },
    "other": {
      "primary": {"model": "gpt-4o"},
      "fallback": {"model": "gpt-4o-mini"}
    }
  },
  "quotas": {
    "anthropic_main": {"total": 1000, "used": 100, "reset_at": "2026-09-01T00:00:00Z"},
    "google_main": {"total": 1000, "used": 1000, "reset_at": "2026-09-01T00:00:00Z"},
    "openai_main": {"total": 1000, "used": 999, "reset_at": "2026-09-01T00:00:00Z"}
  }
}
''';

/// 主额度耗尽的配置（用于 fallback 链测试）。
const exhaustedPrimaryConfigJson = '''
{
  "schema_version": 1,
  "task_routing": {
    "content_generation": {
      "primary": {"model": "claude-sonnet-4", "quota_key": "anthropic_main"},
      "fallback": {"model": "gemini-pro", "quota_key": "google_main"},
      "local": {"model": "local-llm"}
    },
    "other": {
      "primary": {"model": "gpt-4o"},
      "fallback": {"model": "gpt-4o-mini"}
    }
  },
  "quotas": {
    "anthropic_main": {"total": 1000, "used": 1000},
    "google_main": {"total": 1000, "used": 100}
  }
}
''';

void main() {
  group('ModelConfig.fromJson', () {
    test('解析配置：路由与额度', () {
      final config = ModelConfig.fromJson(sampleConfigJson);
      expect(config.schemaVersion, 1);
      expect(config.taskRouting.keys, contains(TaskType.contentGeneration));
      expect(config.taskRouting[TaskType.coding]!.primary.model, 'claude-code');
      expect(config.quotas['anthropic_main']!.total, 1000);
      expect(config.quotas['anthropic_main']!.used, 100);
      expect(config.quotas['anthropic_main']!.resetAt, isNotNull);
    });

    test('未知任务类型键被忽略', () {
      final config = ModelConfig.fromJson(jsonEncode({
        'schema_version': 1,
        'task_routing': {
          'not_a_task_type': {
            'primary': {'model': 'x'},
            'fallback': {'model': 'y'},
          }
        },
        'quotas': {},
      }));
      expect(config.taskRouting, isEmpty);
    });
  });

  group('ModelRouter.selectModel - primary → fallback → local', () {
    test('primary 额度未耗尽 → primary', () {
      final router = ModelRouter(config: ModelConfig.fromJson(sampleConfigJson));
      final selection = router.selectModel(TaskType.contentGeneration);
      expect(selection.model, 'claude-sonnet-4');
      expect(selection.level, FallbackLevel.primary);
      expect(selection.isFallback, isFalse);
    });

    test('primary 耗尽 → fallback（google_main 未耗尽）', () {
      final router =
          ModelRouter(config: ModelConfig.fromJson(exhaustedPrimaryConfigJson));
      final selection = router.selectModel(TaskType.contentGeneration);
      expect(selection.model, 'gemini-pro');
      expect(selection.level, FallbackLevel.fallback);
      expect(selection.isFallback, isTrue);
    });

    test('primary 与 fallback 都耗尽 → local', () {
      final router = ModelRouter(config: ModelConfig.fromJson(jsonEncode({
        'schema_version': 1,
        'task_routing': {
          'content_generation': {
            'primary': {'model': 'claude-sonnet-4', 'quota_key': 'a'},
            'fallback': {'model': 'gemini-pro', 'quota_key': 'b'},
            'local': {'model': 'local-llm'},
          }
        },
        'quotas': {
          'a': {'total': 10, 'used': 10},
          'b': {'total': 10, 'used': 10},
        },
      })));
      final selection = router.selectModel(TaskType.contentGeneration);
      expect(selection.model, 'local-llm');
      expect(selection.level, FallbackLevel.local);
    });

    test('全部耗尽且无 local → ModelUnavailableException', () {
      final router = ModelRouter(config: ModelConfig.fromJson(jsonEncode({
        'schema_version': 1,
        'task_routing': {
          'content_generation': {
            'primary': {'model': 'claude-sonnet-4', 'quota_key': 'a'},
            'fallback': {'model': 'gemini-pro', 'quota_key': 'b'},
          }
        },
        'quotas': {
          'a': {'total': 10, 'used': 10},
          'b': {'total': 10, 'used': 10},
        },
      })));
      expect(
        () => router.selectModel(TaskType.contentGeneration),
        throwsA(isA<ModelUnavailableException>()),
      );
    });

    test('无 quota_key 的模型视为不限量（fail-open）', () {
      final router = ModelRouter(config: ModelConfig.fromJson(jsonEncode({
        'schema_version': 1,
        'task_routing': {
          'other': {
            'primary': {'model': 'gpt-4o'},
            'fallback': {'model': 'gpt-4o-mini'},
          }
        },
        'quotas': {},
      })));
      final selection = router.selectModel(TaskType.other);
      expect(selection.model, 'gpt-4o');
      expect(selection.level, FallbackLevel.primary);
    });

    test('未配置的类型回落到 other 条目', () {
      final router = ModelRouter(config: ModelConfig.fromJson(sampleConfigJson));
      final selection = router.selectModel(TaskType.media);
      expect(selection.model, 'gpt-4o');
    });

    test('配额行存在但 used 略小于 total 不算耗尽', () {
      final router = ModelRouter(config: ModelConfig.fromJson(sampleConfigJson));
      final selection = router.selectModel(TaskType.coding);
      expect(selection.model, 'claude-code');
      expect(selection.level, FallbackLevel.primary);
    });
  });

  group('ModelRouter 文件加载', () {
    test('ModelRouter.fromFile 读取磁盘配置', () {
      final dir = Directory.systemTemp.createTempSync('model_config_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}model_config.json');
      file.writeAsStringSync(sampleConfigJson);

      final router = ModelRouter.fromFile(file.path);
      final selection = router.selectModel(TaskType.contentGeneration);
      expect(selection.model, 'claude-sonnet-4');
      expect(selection.level, FallbackLevel.primary);
    });

    test('文件缺失抛出 StateError', () {
      expect(
        () => ModelRouter.fromFile('D:/definitely/not/exists.json'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
