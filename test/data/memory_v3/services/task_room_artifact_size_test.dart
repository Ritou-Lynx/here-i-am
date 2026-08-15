import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';

void main() {
  late AppDatabase db;
  late TaskRoomService service;
  late String taskId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    TaskRoomService.init(db);
    service = TaskRoomService.instance;

    // Create a test task for artifacts
    taskId = await service.createTaskRoom(
      title: 'Size test task',
      goal: 'Test artifact size limits',
      taskType: TaskType.coding,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('TaskRoomService - Artifact Size Limits', () {
    test('small artifact (< 100KB) can be stored without storageRef', () async {
      final smallContent = {
        'text': 'Small content',
        'data': List.generate(100, (i) => 'line $i'),
      };

      final artifactId = await service.recordArtifact(
        taskId: taskId,
        artifactType: ArtifactType.codeDiff,
        title: 'Small artifact',
        content: smallContent,
      );

      expect(artifactId, isNotEmpty);

      final artifacts = await service.getTaskArtifacts(taskId);
      expect(artifacts.length, 1);
      expect(artifacts[0].sizeBytes, isNotNull);
      expect(artifacts[0].sizeBytes! < 100 * 1024, isTrue);
    });

    test('large artifact (> 100KB) without storageRef throws error', () async {
      // Create content > 100KB
      final largeContent = {
        'data': List.generate(5000, (i) => 'This is a long line of text $i' * 10),
      };

      expect(
        () => service.recordArtifact(
          taskId: taskId,
          artifactType: ArtifactType.codeDiff,
          title: 'Large artifact',
          content: largeContent,
        ),
        throwsArgumentError,
      );
    });

    test('large artifact with storageRef is allowed', () async {
      // Create content > 100KB but provide storageRef
      final largeContent = {
        'data': List.generate(5000, (i) => 'This is a long line of text $i' * 10),
      };

      final artifactId = await service.recordArtifact(
        taskId: taskId,
        artifactType: ArtifactType.codeDiff,
        title: 'Large artifact with ref',
        content: largeContent,
        storageRef: 's3://bucket/large-diff.json',
      );

      expect(artifactId, isNotEmpty);

      final artifacts = await service.getTaskArtifacts(taskId);
      expect(artifacts.length, 1);
      expect(artifacts[0].storageRef, 's3://bucket/large-diff.json');
      expect(artifacts[0].sizeBytes! > 100 * 1024, isTrue);
    });

    test('sizeBytes defaults to content size when not provided', () async {
      final content = {'text': 'Test content'};

      final artifactId = await service.recordArtifact(
        taskId: taskId,
        artifactType: ArtifactType.analysisResult,
        title: 'Auto-sized artifact',
        content: content,
      );

      final artifacts = await service.getTaskArtifacts(taskId);
      expect(artifacts.length, 1);
      expect(artifacts[0].sizeBytes, isNotNull);
      expect(artifacts[0].sizeBytes! > 0, isTrue);
    });

    test('explicit sizeBytes overrides calculated size', () async {
      final content = {'text': 'Small'};

      final artifactId = await service.recordArtifact(
        taskId: taskId,
        artifactType: ArtifactType.screenshot,
        title: 'Image with metadata',
        content: content,
        sizeBytes: 2 * 1024 * 1024, // 2MB original image
        storageRef: 'file://screenshot.png',
      );

      final artifacts = await service.getTaskArtifacts(taskId);
      expect(artifacts.length, 1);
      expect(artifacts[0].sizeBytes, 2 * 1024 * 1024);
    });
  });
}
