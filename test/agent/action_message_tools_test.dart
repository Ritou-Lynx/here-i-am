import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/skills/companion_agent/tools/action_message_tools.dart';
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

  test('identical action tool calls persist only once per agent turn',
      () async {
    final tool =
        ActionMessageToolFactory(characterId: 'i').buildSendActionMessageTool();

    final first = await Function.apply(
      tool.executable!,
      ['*我把手机往枕头边一放，慢慢笑了。*'],
    );
    final duplicate = await Function.apply(
      tool.executable!,
      ['我把手机往枕头边一放，慢慢笑了。'],
    );

    final messages = await db.select(db.personaChatMessages).get();
    expect(first, 'Action message sent.');
    expect(duplicate, contains('already sent'));
    expect(messages, hasLength(1));
    expect(messages.single.messageType, 'action');
    expect(messages.single.content, '*我把手机往枕头边一放，慢慢笑了。*');
  });
}
