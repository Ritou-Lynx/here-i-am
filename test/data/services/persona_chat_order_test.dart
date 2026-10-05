import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/persona_chat_order.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/db/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  final service = PersonaChatService.instance;
  const second = 1700000000000;
  Future<PersonaChatMessage> insert(String text,
      {int? ms, int? sequence, String character = 'i'}) async {
    final id = await db
        .into(db.personaChatMessages)
        .insert(PersonaChatMessagesCompanion.insert(
          characterId: character,
          isFromCharacter: false,
          content: text,
          timestamp: DateTime.fromMillisecondsSinceEpoch(ms ?? second),
          createdAtMs: Value(ms),
          serverSequence: Value(sequence),
        ));
    return (await service.getMessageById(id))!;
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AppDatabase.setTestInstance(db);
  });
  tearDown(() async {
    await db.close();
  });

  test(
      'same-second milliseconds outrank insertion id across list/search/latest/selected export comparator',
      () async {
    final later = await insert('match later', ms: second + 900, sequence: 1);
    final earlier =
        await insert('match earlier', ms: second + 100, sequence: 999);
    expect(later.id, lessThan(earlier.id));
    final expected = [later.id, earlier.id];
    expect((await service.getMessages('i')).map((m) => m.id), expected);
    expect((await service.searchMessages('i', 'match')).map((m) => m.id),
        expected);
    expect((await service.getLastMessage('i'))!.id, later.id);
    expect(await service.countMessagesNewerThan('i', earlier), 1);
    final selection = [later, earlier]..sort(compareChatMessages);
    expect(selection.map((m) => m.id), expected.reversed);
  });

  test(
      'equal milliseconds order by Core sequence then stable local id, including legacy fallbacks',
      () async {
    final high = await insert('match high', ms: second + 100, sequence: 100);
    final low = await insert('match low', ms: second + 100, sequence: 10);
    final tie = await insert('match tie', ms: second + 100, sequence: 100);
    final legacy = await insert('match legacy');
    expect(high.id, lessThan(low.id));
    final expected = [tie.id, high.id, low.id, legacy.id];
    expect((await service.getMessages('i')).map((m) => m.id), expected);
    expect((await service.searchMessages('i', 'match')).map((m) => m.id),
        expected);
    expect((await service.getLastMessage('i'))!.id, tie.id);
    for (final (index, row) in [tie, high, low, legacy].indexed) {
      expect(await service.countMessagesNewerThan('i', row), index);
    }
    final selection = [low, legacy, high, tie]..sort(compareChatMessages);
    expect(selection.map((m) => m.id), expected.reversed);
  });

  test(
      'multi-page listing and search location share exactly the same total order',
      () async {
    final rows = <PersonaChatMessage>[];
    for (var i = 0; i < 37; i++) {
      rows.add(await insert('match $i',
          ms: second + (i % 4) * 11, sequence: i.isEven ? 100 - i : null));
    }
    await insert('match other character',
        ms: second + 999, sequence: 999, character: 'other');
    final ascending = [...rows]..sort(compareChatMessages);
    final expected = ascending.reversed.toList();
    final paged = <PersonaChatMessage>[];
    for (var offset = 0; offset < rows.length; offset += 7) {
      paged.addAll(await service.getMessages('i', limit: 7, offset: offset));
    }
    expect(paged.map((m) => m.id), expected.map((m) => m.id));
    expect(paged.map((m) => m.id).toSet(), hasLength(37));
    expect(
        (await service.searchMessages('i', 'match', limit: 40))
            .map((m) => m.id),
        expected.map((m) => m.id));
    for (final (index, row) in expected.indexed) {
      final newerCount = await service.countMessagesNewerThan('i', row);
      expect(newerCount, index);
      final located =
          await service.getMessages('i', offset: newerCount, limit: 1);
      expect(located.single.id, row.id);
    }
    expect((await service.getLastMessage('i'))!.id, expected.first.id);
  });
}
