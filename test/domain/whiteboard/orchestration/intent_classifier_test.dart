import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/domain/whiteboard/orchestration/intent_classifier.dart';

void main() {
  final classifier = IntentClassifier();

  group('IntentClassifier - 规则 + 关键词', () {
    test('内容生成：帮我生成一张卡片', () {
      final intent = classifier.classify('帮我生成一张关于现代主义建筑的卡片');
      expect(intent.type, TaskType.contentGeneration);
      expect(intent.confidence, 1.0);
      expect(intent.matchedKeywords, containsAll(['生成', '卡片']));
    });

    test('内容生成：写一篇长文', () {
      final intent = classifier.classify('写一篇关于量子计算的文章');
      expect(intent.type, TaskType.contentGeneration);
    });

    test('coding：帮我添加导出功能', () {
      final intent = classifier.classify('帮我把这个导出功能加上，支持 JSON 格式');
      expect(intent.type, TaskType.coding);
    });

    test('debugging：报错 / 崩溃', () {
      expect(classifier.classify('应用一直报错，帮我排查一下').type,
          TaskType.debugging);
      expect(classifier.classify('为什么启动就崩溃').type, TaskType.debugging);
    });

    test('media：分析这张图片（平局裁决 media > research）', () {
      final intent = classifier.classify('分析这张图片');
      expect(intent.type, TaskType.media);
    });

    test('research：调研', () {
      expect(classifier.classify('帮我调研一下这个技术方案').type, TaskType.research);
    });

    test('planning：计划安排', () {
      expect(classifier.classify('帮我计划周末的安排').type, TaskType.planning);
    });

    test('linkIngestion：保存链接', () {
      final intent = classifier.classify('把这个链接保存一下 https://example.com');
      expect(intent.type, TaskType.linkIngestion);
    });

    test('whiteboard：放到白板', () {
      expect(classifier.classify('把这五张图放到白板上').type, TaskType.whiteboard);
    });

    test('未知消息 → other，置信度 0', () {
      final intent = classifier.classify('今天天气怎么样');
      expect(intent.type, TaskType.other);
      expect(intent.confidence, 0.0);
      expect(intent.matchedKeywords, isEmpty);
    });

    test('空消息 → other', () {
      expect(classifier.classify('   ').type, TaskType.other);
    });

    test('单关键词命中置信度 0.6', () {
      final intent = classifier.classify('帮我分析一下');
      expect(intent.type, TaskType.research);
      expect(intent.confidence, 0.6);
    });

    test('大小写不敏感（BUG）', () {
      expect(classifier.classify('这个 BUG 怎么处理').type, TaskType.coding);
    });
  });
}
