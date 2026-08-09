import 'package:flutter_test/flutter_test.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TTS provider defaults to MiniMax when no choice was stored', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await UserStorage.getTtsProvider(), 'minimax');
    expect(UserStorage.getCachedTtsProviderSync(), 'minimax');
  });

  test('an explicit TTS provider choice remains persisted', () async {
    SharedPreferences.setMockInitialValues({});

    await UserStorage.setTtsProvider('elevenlabs');

    expect(await UserStorage.getTtsProvider(), 'elevenlabs');
  });
}
