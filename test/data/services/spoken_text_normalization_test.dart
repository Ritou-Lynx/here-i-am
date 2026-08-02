import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/elevenlabs_tts_service.dart';

void main() {
  group('normalizeSpokenText', () {
    test('plain integer', () {
      expect(ElevenLabsTtsService.normalizeSpokenText('391 项'),
          '三百九十一 项');
      expect(ElevenLabsTtsService.normalizeSpokenText('15 分钟'), '十五 分钟');
      expect(ElevenLabsTtsService.normalizeSpokenText('1001 夜'), '一千零一 夜');
      expect(ElevenLabsTtsService.normalizeSpokenText('0'), '零');
    });

    test('date formats', () {
      expect(
          ElevenLabsTtsService.normalizeSpokenText('2026-06-18 上午10:43'),
          '二零二六年六月十八日 上午十点四十三分');
      expect(ElevenLabsTtsService.normalizeSpokenText('2026年6月18日'),
          '二零二六年六月十八日');
      expect(ElevenLabsTtsService.normalizeSpokenText('2026/6/18'),
          '二零二六年六月十八日');
      // 带空格不识别为日期，按普通数字读
      expect(ElevenLabsTtsService.normalizeSpokenText('2026 年'),
          '二千零二十六 年');
    });

    test('money', () {
      expect(ElevenLabsTtsService.normalizeSpokenText('￥39.9'), '三十九块九');
      expect(ElevenLabsTtsService.normalizeSpokenText('¥39.9'), '三十九块九');
      expect(ElevenLabsTtsService.normalizeSpokenText('39元'), '三十九块');
      expect(ElevenLabsTtsService.normalizeSpokenText('20块钱'), '二十块');
      expect(ElevenLabsTtsService.normalizeSpokenText('0.5元'), '五毛');
      expect(ElevenLabsTtsService.normalizeSpokenText('0.05元'), '五分');
      // 裸小数按点读
      expect(ElevenLabsTtsService.normalizeSpokenText('39.99'), '三十九点九九');
    });

    test('percent and time', () {
      expect(ElevenLabsTtsService.normalizeSpokenText('50%'), '百分之五十');
      expect(ElevenLabsTtsService.normalizeSpokenText('12:30'), '十二点三十分');
      expect(ElevenLabsTtsService.normalizeSpokenText('9:00'), '九点');
      expect(ElevenLabsTtsService.normalizeSpokenText('8:05'), '八点零五分');
    });

    test('fraction and phone', () {
      expect(ElevenLabsTtsService.normalizeSpokenText('3/4'), '四分之三');
      expect(ElevenLabsTtsService.normalizeSpokenText('13800138000'),
          '幺三八零零幺三八零零零');
    });

    test('range and decimal', () {
      expect(ElevenLabsTtsService.normalizeSpokenText('2-3 小时'), '二到三 小时');
      expect(ElevenLabsTtsService.normalizeSpokenText('3.14'), '三点一四');
    });

    test('keyboard shortcuts', () {
      expect(ElevenLabsTtsService.normalizeSpokenText('Ctrl+C'), '复制');
      expect(ElevenLabsTtsService.normalizeSpokenText('ctrl+v'), '粘贴');
      expect(ElevenLabsTtsService.normalizeSpokenText('Ctrl+Q'), 'control 加 Q');
    });

    test('long numbers read digit by digit', () {
      expect(ElevenLabsTtsService.normalizeSpokenText('订单号 12345'),
          '订单号 一二三四五');
    });

    test('numbers glued to Latin letters are left alone', () {
      expect(ElevenLabsTtsService.normalizeSpokenText('v3 版本'), 'v3 版本');
      expect(ElevenLabsTtsService.normalizeSpokenText('iPhone15'), 'iPhone15');
      expect(ElevenLabsTtsService.normalizeSpokenText('5G 网络'), '5G 网络');
    });

    test('Chinese text untouched', () {
      expect(ElevenLabsTtsService.normalizeSpokenText('今天天气真好'),
          '今天天气真好');
      expect(ElevenLabsTtsService.normalizeSpokenText('[softly] 晚安'),
          '[softly] 晚安');
    });
  });
}
