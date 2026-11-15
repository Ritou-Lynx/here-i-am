import 'package:flutter_test/flutter_test.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stored avatar values are returned without migration', () async {
    SharedPreferences.setMockInitialValues({'user_avatar': '🙂'});

    expect(await UserStorage.getUserAvatar(), '🙂');
  });

  test('saving an avatar only persists the selected value', () async {
    SharedPreferences.setMockInitialValues({});

    await UserStorage.saveUserAvatar('custom/avatar.png');

    expect(await UserStorage.getUserAvatar(), 'custom/avatar.png');
  });
}
