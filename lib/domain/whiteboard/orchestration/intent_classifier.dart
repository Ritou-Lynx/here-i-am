/// 规则 + 关键词的意图分类器（W5 Phase 2）。
///
/// 纯 domain、无 IO：输入一句用户消息，输出一个 [TaskIntent]。
/// 使用打分制：每个任务类型有一组关键词，命中数即分数；
/// 平局时按 [_tieBreakPriority] 的顺序裁决；零命中归类为 [TaskType.other]。
library;

import '../../../data/memory_v3/models/task_room_enums.dart';

/// 意图分类结果。
class TaskIntent {
  /// 归类出的任务类型。
  final TaskType type;

  /// 置信度 0.0–1.0：≥2 个关键词命中为 1.0，1 个命中为 0.6，无命中为 0.0。
  final double confidence;

  /// 命中的关键词。
  final List<String> matchedKeywords;

  /// 原始消息（便于下游定位）。
  final String rawMessage;

  const TaskIntent({
    required this.type,
    required this.confidence,
    this.matchedKeywords = const [],
    this.rawMessage = '',
  });
}

/// 规则 + 关键词的意图分类器。
class IntentClassifier {
  /// 各任务类型的关键词表（消息按小写包含匹配）。
  static const Map<TaskType, List<String>> keywordTable = {
    TaskType.debugging: [
      '报错',
      '错误',
      '异常',
      '崩溃',
      '闪退',
      '排查',
      '调试',
      '出错',
      '故障',
      '修一下',
      '修复',
    ],
    TaskType.coding: [
      '代码',
      '编程',
      '写个',
      '实现',
      '重构',
      '函数',
      '接口',
      '算法',
      '脚本',
      '自动化',
      '导出',
      '命令',
      '工具',
      '编译',
      '模块',
      'bug',
      'sql',
      '修复',
    ],
    TaskType.contentGeneration: [
      '卡片',
      '生成',
      '文章',
      '写一篇',
      '文案',
      '摘要',
      '总结',
      '长文',
      '笔记',
      '介绍',
      '大纲',
      '标题',
      '内容',
    ],
    TaskType.media: [
      '图片',
      '视频',
      '截图',
      '照片',
      '字幕',
      '音频',
    ],
    TaskType.research: [
      '研究',
      '调研',
      '查一下',
      '搜索',
      '资料',
      '分析',
      '学习',
      '了解',
      '对比',
      '原因',
      '报告',
    ],
    TaskType.planning: [
      '计划',
      '规划',
      '安排',
      '方案',
      '排期',
      '路线图',
      '目标',
      '步骤',
    ],
    TaskType.linkIngestion: [
      '链接',
      'url',
      'http',
      '抓取',
      '导入',
      '网页',
      '网址',
    ],
    TaskType.whiteboard: [
      '白板',
      '画布',
      '放板上',
      '摆到板',
      '放白板',
    ],
  };

  /// 平局裁决优先级（越靠前越优先）。
  ///
  /// 「分析这张图片」同时命中 research(分析) 与 media(图片) 时按此顺序归 media。
  static const List<TaskType> tieBreakPriority = [
    TaskType.media,
    TaskType.debugging,
    TaskType.coding,
    TaskType.contentGeneration,
    TaskType.research,
    TaskType.linkIngestion,
    TaskType.planning,
    TaskType.whiteboard,
  ];

  /// 分类一句用户消息。
  TaskIntent classify(String message) {
    final raw = message.trim().toLowerCase();
    if (raw.isEmpty) {
      return const TaskIntent(
        type: TaskType.other,
        confidence: 0,
        rawMessage: '',
      );
    }

    var bestType = TaskType.other;
    var bestScore = 0;
    var bestKeywords = <String>[];

    for (final entry in keywordTable.entries) {
      final hits = <String>[];
      for (final keyword in entry.value) {
        if (raw.contains(keyword.toLowerCase())) {
          hits.add(keyword);
        }
      }
      if (hits.isEmpty) continue;

      final score = hits.length;
      final better =
          score > bestScore ||
          (score == bestScore &&
              tieBreakPriority.indexOf(entry.key) <
                  tieBreakPriority.indexOf(bestType));
      if (better) {
        bestType = entry.key;
        bestScore = score;
        bestKeywords = hits;
      }
    }

    final confidence = bestScore >= 2
        ? 1.0
        : bestScore == 1
            ? 0.6
            : 0.0;

    return TaskIntent(
      type: bestType,
      confidence: confidence,
      matchedKeywords: bestKeywords,
      rawMessage: message,
    );
  }
}
