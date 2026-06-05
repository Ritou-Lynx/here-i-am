import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/active_persona_chat_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('tracks only the currently visible persona chat', () async {
    final service = ActivePersonaChatService.instance;

    await service.markActive('char-a');

    expect(await service.isActive('char-a'), isTrue);
    expect(await service.isActive('char-b'), isFalse);

    await service.clear(characterId: 'char-b');
    expect(await service.isActive('char-a'), isTrue);

    await service.clear(characterId: 'char-a');
    expect(await service.isActive('char-a'), isFalse);
  });
}
