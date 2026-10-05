import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/skills/character_tools_factory.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/services/device_identity_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/companion/view_models/schedule_view_model.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late Directory tempRoot;
  late RecordOrganizerServiceV3 organizer;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DeviceIdentityService.resetForTesting();
    await UserStorage.initL10n();
    tempRoot = await Directory.systemTemp.createTemp('memory_user_turn_');
    await FileSystemService.init(tempRoot.path);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AppDatabase.setTestInstance(db);
    RecordOrganizerServiceV3.init(db);
    organizer = RecordOrganizerServiceV3.instance;
    await db.customSelect('SELECT 1').get();
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    RecordOrganizerServiceV3.reset();
    await db.close();
    await tempRoot.delete(recursive: true);
  });

  Tool toolFor(int? messageId) => CharacterToolsFactory.buildCompanionTools(
        userId: 'fixture-user',
        characterId: 'primary',
        currentUserMessageId: messageId,
      ).singleWhere((tool) => tool.name == 'memory_v3_update_card');

  Future<Map<String, dynamic>> invoke(
      Tool tool, Map<String, dynamic> args) async {
    expect(tool.parameterMode, ToolParameterMode.object);
    final result = await Function.apply(tool.executable!, [args]);
    return jsonDecode(result as String) as Map<String, dynamic>;
  }

  Future<String> seedCard(String title) async {
    final result = await organizer.persist(
      organized: OrganizedRecord(cards: [
        OrganizedCard(
          type: 'task',
          status: 'active',
          title: title,
          dropletLabel: '合成',
          presentationModule: {'blocks': <dynamic>[]},
          retrievalText: title,
          valence: 0,
          arousal: 0,
        ),
      ]),
      source: RecordSource(sourceKind: 'record_button', rawInput: title),
    );
    return result.cardIds.single;
  }

  Future<int> userMessage(String content, {String character = 'primary'}) =>
      PersonaChatService.instance.addUserMessage(character, content);
  Future<PersonaChatMessage> message(int id) =>
      (db.select(db.personaChatMessages)..where((t) => t.id.equals(id)))
          .getSingle();
  Future<List<Map<String, dynamic>>> updates(String cardId) async =>
      (await (db.select(db.memoryCardOperations)
                ..where((t) =>
                    t.cardId.equals(cardId) & t.operationType.equals('update')))
              .get())
          .map((op) => jsonDecode(op.payload) as Map<String, dynamic>)
          .toList();

  test('schedule completion then real user turn reopens through factory tool',
      () async {
    final cardId = await seedCard('Synthetic schedule');
    final vm = ScheduleViewModel(queryService: MemoryCardQueryService(db));
    addTearDown(vm.dispose);
    await vm.load.execute();
    await vm.toggleComplete.execute(cardId);
    expect(vm.toggleComplete.error, false);
    expect((await MemoryCardQueryService(db).getCardDetail(cardId)).card.status,
        'completed');
    final triggerId = await userMessage('把这条日程改回未完成');
    final tool = toolFor(triggerId);
    await userMessage('这是一条与修改无关的后续消息');
    final result = await invoke(tool, {'card_id': cardId, 'status': 'active'});
    expect(result['success'], true, reason: '$result');
    expect((await MemoryCardQueryService(db).getCardDetail(cardId)).card.status,
        'active');
    final audit = await updates(cardId);
    expect(
        audit.map((row) => row['_actor']), ['user_direct', 'user_via_agent']);
    expect(audit.last['_authorization_ref'], (await message(triggerId)).syncId);
    final corrections = await (db.select(db.userCorrections)
          ..where((t) => t.targetId.equals(cardId) & t.field.equals('status')))
        .get();
    final actors = await (db.select(db.kvStore)
          ..where((t) => t.key.isIn(
              corrections.map((row) => 'user_correction_actor.${row.id}'))))
        .get();
    expect(actors.map((row) => row.value),
        containsAll(['user_direct', 'user_via_agent']));
  });

  test('missing turn or message cannot adopt a recent real user message',
      () async {
    final cardId = await seedCard('Missing context');
    await userMessage('最近的真实用户消息不代表本轮授权');
    for (final entry in <int?, String>{
      null: 'missing_user_turn_context',
      999999: 'trigger_message_not_found',
    }.entries) {
      final result = await invoke(
          toolFor(entry.key), {'card_id': cardId, 'title': 'must not write'});
      expect(result['error'], entry.value);
    }
    expect(await updates(cardId), isEmpty);
  });

  test('non-user and non-chat messages cannot authorize edits', () async {
    final cardId = await seedCard('No system authorization');
    for (final isCharacter in [true, false]) {
      final id = await db.into(db.personaChatMessages).insert(
            PersonaChatMessagesCompanion.insert(
              characterId: 'primary',
              isFromCharacter: isCharacter,
              messageType: Value(isCharacter ? 'chat' : 'action'),
              syncId: Value('synthetic-$isCharacter'),
              content: 'synthetic message',
              timestamp: DateTime(2026, 10, 5),
            ),
          );
      expect(
          (await invoke(
              toolFor(id), {'card_id': cardId, 'title': 'bad'}))['error'],
          'trigger_message_not_user_chat');
    }
    expect(await updates(cardId), isEmpty);
  });

  test('wrong character and task room fail even with valid user sync IDs',
      () async {
    final cardId = await seedCard('Conversation isolation');
    final other = await userMessage('另一角色会话', character: 'other');
    final room = await userMessage('另一工作台线程');
    await (db.update(db.personaChatMessages)..where((t) => t.id.equals(room)))
        .write(const PersonaChatMessagesCompanion(taskRoomId: Value('room-a')));
    for (final id in [other, room]) {
      expect(
          (await invoke(
              toolFor(id), {'card_id': cardId, 'title': 'bad'}))['error'],
          'trigger_message_wrong_conversation');
    }
    expect(await updates(cardId), isEmpty);
  });

  test('missing sync ID fails without agent_inferred downgrade', () async {
    final cardId = await seedCard('Stable provenance required');
    final id = await userMessage('修改标题');
    for (final syncId in <String?>[null, '', '   ']) {
      await (db.update(db.personaChatMessages)..where((t) => t.id.equals(id)))
          .write(PersonaChatMessagesCompanion(syncId: Value(syncId)));
      expect(
          (await invoke(
              toolFor(id), {'card_id': cardId, 'title': 'bad'}))['error'],
          'trigger_message_missing_sync_id');
    }
    expect(await updates(cardId), isEmpty);
  });

  test(
      'model arguments cannot forge actor, message, character or authorization',
      () async {
    final cardId = await seedCard('No forged authorization');
    final id = await userMessage('修改标题');
    for (final field in [
      'actor',
      'authorizationRef',
      'authorization_ref',
      'currentUserMessageId',
      'sourceMessageId',
      'characterId',
    ]) {
      for (final tool in [toolFor(null), toolFor(id)]) {
        expect(
            (tool.parameters['properties'] as Map).containsKey(field), false);
        expect(
            (await invoke(tool, {
              'card_id': cardId,
              'title': 'forged',
              field: 'forged',
            }))['error'],
            'unsupported_argument');
      }
    }
    expect(await updates(cardId), isEmpty);
  });

  test('overlapping turns preserve their own message authorization', () async {
    final a = await seedCard('Concurrent A');
    final b = await seedCard('Concurrent B');
    final idA = await userMessage('改第一条标题');
    final toolA = toolFor(idA);
    final idB = await userMessage('改第二条标题');
    final toolB = toolFor(idB);
    final results = await Future.wait([
      invoke(toolB, {'card_id': b, 'title': 'B edited'}),
      invoke(toolA, {'card_id': a, 'title': 'A edited'}),
    ]);
    expect(results.every((result) => result['success'] == true), true,
        reason: '$results');
    expect((await updates(a)).single['_authorization_ref'],
        (await message(idA)).syncId);
    expect((await updates(b)).single['_authorization_ref'],
        (await message(idB)).syncId);
  });
}
