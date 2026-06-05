import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/companion_agent/recent_activity_snapshot.dart';
import 'package:memex/db/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AppDatabase.setTestInstance(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('snapshot includes a recent chat window for ongoing context', () async {
    final now = DateTime.now();

    Future<void> insertMessage({
      required bool fromCharacter,
      required String content,
      required int minutesAgo,
    }) async {
      await db.into(db.personaChatMessages).insert(
            PersonaChatMessagesCompanion.insert(
              characterId: 'char-1',
              isFromCharacter: fromCharacter,
              content: content,
              timestamp: now.subtract(Duration(minutes: minutesAgo)),
            ),
          );
    }

    await insertMessage(
      fromCharacter: true,
      content: '海龟汤开始：一个人走进餐厅点了一碗海龟汤。',
      minutesAgo: 7,
    );
    await insertMessage(
      fromCharacter: false,
      content: '他以前喝过真正的海龟汤吗？',
      minutesAgo: 6,
    );
    await insertMessage(
      fromCharacter: true,
      content: '是。',
      minutesAgo: 5,
    );
    await insertMessage(
      fromCharacter: false,
      content: '所以他发现这次味道不一样？',
      minutesAgo: 4,
    );

    final snapshot = await RecentActivitySnapshot.build(
      userId: 'user-1',
      characterId: 'char-1',
    );

    expect(snapshot, contains('Recent chat window (oldest to newest):'));
    expect(snapshot, contains('海龟汤开始'));
    expect(snapshot, contains('他以前喝过真正的海龟汤吗'));
    expect(snapshot, contains('所以他发现这次味道不一样'));
  });
}
