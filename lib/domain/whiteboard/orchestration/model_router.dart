/// 模型路由与额度检查（W5 Phase 2）。
///
/// 按任务类型选择模型：primary → fallback → local。
/// 配置读取 `~/.hereiam/whiteboard/model_config.json`，格式见 W5 文档 § 4.2。
/// 纯 domain：只有 dart:io 的配置文件加载，不依赖任何 Memex 代码。
library;

import 'dart:convert';
import 'dart:io';

import '../../../data/memory_v3/models/task_room_enums.dart';

/// fallback 链的层级。
enum FallbackLevel {
  /// 首选模型
  primary,

  /// 备用模型
  fallback,

  /// 本地模型（所有付费模型耗尽时降级）
  local,
}

/// 一次模型选择的结果。
class ModelSelection {
  final String model;
  final String? quotaKey;
  final FallbackLevel level;

  const ModelSelection({
    required this.model,
    this.quotaKey,
    required this.level,
  });

  /// 是否走过了 fallback（primary 之外的任何层级）。
  bool get isFallback => level != FallbackLevel.primary;

  @override
  String toString() => 'ModelSelection($model, ${level.name})';
}

/// 单一模型引用（模型名 + 可选额度 key）。
class ModelRef {
  final String model;
  final String? quotaKey;

  const ModelRef({required this.model, this.quotaKey});

  factory ModelRef.fromJson(Map<String, dynamic> json) {
    return ModelRef(
      model: json['model'] as String,
      quotaKey: json['quota_key'] as String?,
    );
  }
}

/// 一个任务类型的路由条目：primary / fallback / local。
class ModelRouteEntry {
  final ModelRef primary;
  final ModelRef fallback;
  final ModelRef? local;

  const ModelRouteEntry({
    required this.primary,
    required this.fallback,
    this.local,
  });

  factory ModelRouteEntry.fromJson(Map<String, dynamic> json) {
    return ModelRouteEntry(
      primary: ModelRef.fromJson(json['primary'] as Map<String, dynamic>),
      fallback: ModelRef.fromJson(json['fallback'] as Map<String, dynamic>),
      local: json['local'] != null
          ? ModelRef.fromJson(json['local'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// 额度（token 预算）。
class Quota {
  final int total;
  final int used;
  final DateTime? resetAt;

  const Quota({required this.total, required this.used, this.resetAt});

  bool get exhausted => used >= total;

  factory Quota.fromJson(Map<String, dynamic> json) {
    return Quota(
      total: (json['total'] as num).toInt(),
      used: (json['used'] as num).toInt(),
      resetAt: json['reset_at'] != null
          ? DateTime.tryParse(json['reset_at'] as String)
          : null,
    );
  }
}

/// 模型配置（`model_config.json` 的解析结果）。
class ModelConfig {
  final int schemaVersion;
  final Map<TaskType, ModelRouteEntry> taskRouting;
  final Map<String, Quota> quotas;

  const ModelConfig({
    this.schemaVersion = 1,
    this.taskRouting = const {},
    this.quotas = const {},
  });

  factory ModelConfig.fromJson(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final routing = <TaskType, ModelRouteEntry>{};
    final rawRouting = decoded['task_routing'] as Map<String, dynamic>? ?? {};
    rawRouting.forEach((key, value) {
      final type = TaskType.values
          .where((t) => t.value == key)
          .firstOrNull;
      if (type != null) {
        routing[type] = ModelRouteEntry.fromJson(value as Map<String, dynamic>);
      }
    });

    final quotas = <String, Quota>{};
    final rawQuotas = decoded['quotas'] as Map<String, dynamic>? ?? {};
    rawQuotas.forEach((key, value) {
      quotas[key] = Quota.fromJson(value as Map<String, dynamic>);
    });

    return ModelConfig(
      schemaVersion: (decoded['schema_version'] as num?)?.toInt() ?? 1,
      taskRouting: routing,
      quotas: quotas,
    );
  }

  Quota? quotaFor(String? quotaKey) {
    if (quotaKey == null) return null;
    return quotas[quotaKey];
  }
}

/// 所有模型都不可用时抛出。
class ModelUnavailableException implements Exception {
  final TaskType taskType;
  final String message;

  ModelUnavailableException(this.taskType, this.message);

  @override
  String toString() => 'ModelUnavailableException($message)';
}

/// 模型路由器：按任务类型选择模型并做额度检查。
class ModelRouter {
  final ModelConfig config;

  ModelRouter({required this.config});

  /// 从 `~/.hereiam/whiteboard/model_config.json` 加载。
  ///
  /// [homeOverride] 仅用于测试 / 自定义目录；默认取 HOME / USERPROFILE。
  factory ModelRouter.fromHomeConfigFile({String? homeOverride}) {
    final home = homeOverride ??
        (Platform.isWindows
            ? Platform.environment['USERPROFILE']
            : Platform.environment['HOME']);
    if (home == null || home.isEmpty) {
      throw StateError(
          'Cannot locate home directory for model config (HOME/USERPROFILE unset)');
    }
    final path = '$home${Platform.pathSeparator}.hereiam'
        '${Platform.pathSeparator}whiteboard'
        '${Platform.pathSeparator}model_config.json';
    return ModelRouter.fromFile(path);
  }

  /// 从指定文件路径加载配置。
  factory ModelRouter.fromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError(
          'Model config not found: $path. '
          'Create ~/.hereiam/whiteboard/model_config.json (see W5_AI_ORCHESTRATION.md § 4.2).');
    }
    return ModelRouter(config: ModelConfig.fromJson(file.readAsStringSync()));
  }

  /// 选择模型：primary → fallback → local，额度耗尽自动降级。
  ///
  /// 全链耗尽时抛 [ModelUnavailableException]。
  ModelSelection selectModel(TaskType taskType) {
    final entry = config.taskRouting[taskType] ??
        config.taskRouting[TaskType.other];
    if (entry == null) {
      throw ModelUnavailableException(
        taskType,
        'No model routing configured for ${taskType.value} (need at least an "other" fallback entry)',
      );
    }

    if (!_exhausted(entry.primary)) {
      return ModelSelection(
        model: entry.primary.model,
        quotaKey: entry.primary.quotaKey,
        level: FallbackLevel.primary,
      );
    }
    if (!_exhausted(entry.fallback)) {
      return ModelSelection(
        model: entry.fallback.model,
        quotaKey: entry.fallback.quotaKey,
        level: FallbackLevel.fallback,
      );
    }
    final local = entry.local;
    if (local != null && !_exhausted(local)) {
      return ModelSelection(
        model: local.model,
        quotaKey: local.quotaKey,
        level: FallbackLevel.local,
      );
    }

    throw ModelUnavailableException(
      taskType,
      'All models exhausted for ${taskType.value} '
      '(primary=${entry.primary.model}, fallback=${entry.fallback.model}'
      '${local != null ? ', local=${local.model}' : ''})',
    );
  }

  bool _exhausted(ModelRef ref) {
    final quota = config.quotaFor(ref.quotaKey);
    // 没有配额记录的模型视为不限量（fail-open）；有记录且用尽才算耗尽。
    if (quota == null) return false;
    return quota.exhausted;
  }
}
