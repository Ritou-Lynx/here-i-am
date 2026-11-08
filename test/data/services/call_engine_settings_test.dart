import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/call_engine_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('没有新键时迁移读取催睡旧键', () async {
    SharedPreferences.setMockInitialValues({'sleep_nudge.engine': 'classic'});
    expect(await CallEngineSettings.get(), CallEngine.classic);
  });

  test('新旧键都没有时默认 GPT-Live', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await CallEngineSettings.get(), CallEngine.gptLive);
  });

  test('新键优先并可保存', () async {
    SharedPreferences.setMockInitialValues({'sleep_nudge.engine': 'classic'});
    await CallEngineSettings.set(CallEngine.gptLive);
    expect(await CallEngineSettings.get(), CallEngine.gptLive);
  });
}
