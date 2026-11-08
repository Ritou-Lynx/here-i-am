import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/gpt_live/gpt_live_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('静音自动挂断默认 5 分钟且负数按 0 处理', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await GptLiveSettings.getIdleHangupMinutes(), 5);

    await GptLiveSettings.setIdleHangupMinutes(-1);
    expect(await GptLiveSettings.getIdleHangupMinutes(), 0);
  });
}
