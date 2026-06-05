import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/built_in_tools/user_knowledge_query_tool.dart';
import 'package:memex/agent/context/user_knowledge_context_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/card_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late AppDatabase db;
  const userId = 'knowledge-query-user';
  const factId = '2026/06/02.md#ts_1';

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('knowledge_query_');
    await FileSystemService.init(tempRoot.path);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AppDatabase.setTestInstance(db);
    await db.searchDao.createFtsTables();

    final fs = FileSystemService.instance;
    final factFile = File(fs.getDailyFactPath(userId, DateTime(2026, 6, 2)));
    await factFile.parent.create(recursive: true);
    await factFile.writeAsString(
      '## <id:ts_1> 09:30:00\n'
      'The user adopted a cat named Momo.\n',
    );
    await fs.safeWriteCardFile(
      userId,
      factId,
      const CardData(
        factId: factId,
        timestamp: 1780363800,
        status: 'completed',
        tags: ['pet'],
        uiConfigs: [],
        title: 'Adopted Momo',
      ),
    );
    await db.searchDao.upsertCardFts(
      factId: factId,
      title: 'Adopted Momo',
      tags: 'pet',
      content: 'The user adopted a cat named Momo.',
      insight: '',
    );
  });

  tearDown(() async {
    await db.close();
    await tempRoot.delete(recursive: true);
  });

  test('knowledge context retrieves a legacy timeline card without PKM files',
      () async {
    final context =
        await UserKnowledgeContextService.instance.buildKnowledgeCards(
      userId: userId,
      queryHint: 'Momo',
    );

    expect(context, contains('### Timeline card · $factId'));
    expect(context, contains('Adopted Momo'));
    expect(context, contains('The user adopted a cat named Momo.'));
  });

  test('query tool exposes legacy timeline card results to companion',
      () async {
    final tool = buildUserKnowledgeQueryTool(userId: userId);
    final output = await tool.executable!({'query': 'Momo'}) as String;
    final result = Map<String, dynamic>.from(jsonDecode(output) as Map);

    expect(result['success'], isTrue);
    expect(result['context'], contains('### Timeline card · $factId'));
    expect(result['context'], contains('Adopted Momo'));
  });
}
