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

  test('后台模型默认 client、可保存空串和 Responses 模型，非法值回退默认', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await GptLiveSettings.getDelegateModel(), 'client');
    expect(delegateModelOptions['client'], '手机端助手（可查日记/健康/饮食/记账/高驰）');

    await GptLiveSettings.setDelegateModel('');
    expect(await GptLiveSettings.getDelegateModel(), '');

    for (final model in const ['gpt-5.6-luna', 'gpt-5.6-terra', 'gpt-5.6-sol']) {
      await GptLiveSettings.setDelegateModel(model);
      expect(await GptLiveSettings.getDelegateModel(), model);
    }

    SharedPreferences.setMockInitialValues({
      'gpt_live.delegate_model': 'not-a-model',
    });
    expect(await GptLiveSettings.getDelegateModel(), 'client');
  });
}
