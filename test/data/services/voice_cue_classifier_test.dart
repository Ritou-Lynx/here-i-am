import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/voice_cue_classifier.dart';

void main() {
  group('VoiceCueClassifier', () {
    test('empty text returns none', () {
      expect(VoiceCueClassifier.classify(''), VoiceCueClass.none);
      expect(VoiceCueClassifier.classify('   '), VoiceCueClass.none);
    });

    test('farewell detected', () {
      expect(VoiceCueClassifier.classify('我先挂了'), VoiceCueClass.farewell);
      expect(VoiceCueClassifier.classify('挂了'), VoiceCueClass.farewell);
      expect(VoiceCueClassifier.classify('再见'), VoiceCueClass.farewell);
      expect(VoiceCueClassifier.classify('拜拜'), VoiceCueClass.farewell);
      expect(VoiceCueClassifier.classify('bye'), VoiceCueClass.farewell);
      expect(VoiceCueClassifier.classify('没事了'), VoiceCueClass.farewell);
    });

    test('call state question detected', () {
      expect(VoiceCueClassifier.classify('你能听到吗'),
          VoiceCueClass.callStateQuestion);
      expect(VoiceCueClassifier.classify('听得到吗'),
          VoiceCueClass.callStateQuestion);
      expect(VoiceCueClassifier.classify('你在吗'),
          VoiceCueClass.callStateQuestion);
      expect(VoiceCueClassifier.classify('喂'),
          VoiceCueClass.callStateQuestion);
      expect(VoiceCueClassifier.classify('hello'),
          VoiceCueClass.callStateQuestion);
    });

    test('explicit search detected', () {
      expect(VoiceCueClassifier.classify('帮我找一下面馆'),
          VoiceCueClass.searchLeadIn);
      expect(VoiceCueClassifier.classify('搜一下附近的咖啡店'),
          VoiceCueClass.searchLeadIn);
      expect(VoiceCueClassifier.classify('查一下天气'),
          VoiceCueClass.searchLeadIn);
      expect(VoiceCueClassifier.classify('附近有什么好吃的'),
          VoiceCueClass.searchLeadIn);
    });

    test('test context detected', () {
      expect(VoiceCueClassifier.classify('试一下延迟'),
          VoiceCueClass.testLeadIn);
      expect(VoiceCueClassifier.classify('测试一下'),
          VoiceCueClass.testLeadIn);
    });

    test('reflective question detected', () {
      expect(VoiceCueClassifier.classify('你觉得这个怎么样'),
          VoiceCueClass.thinkingLeadIn);
      expect(VoiceCueClassifier.classify('为什么会这样'),
          VoiceCueClass.thinkingLeadIn);
      expect(VoiceCueClassifier.classify('怎么才能学好'),
          VoiceCueClass.thinkingLeadIn);
      expect(VoiceCueClassifier.classify('今天天气好吗？'),
          VoiceCueClass.thinkingLeadIn);
      expect(VoiceCueClassifier.classify('can you help?'),
          VoiceCueClass.thinkingLeadIn);
    });

    test('personal sharing detected', () {
      expect(VoiceCueClassifier.classify('我今天好累'),
          VoiceCueClass.sharingAck);
      expect(VoiceCueClassifier.classify('我刚才遇到一个有趣的事'),
          VoiceCueClass.sharingAck);
      expect(VoiceCueClassifier.classify('你知道吗，我今天很开心'),
          VoiceCueClass.sharingAck);
    });

    test('fun detected', () {
      expect(VoiceCueClassifier.classify('哈哈哈太搞笑了'),
          VoiceCueClass.funAck);
      expect(VoiceCueClassifier.classify('这个好有趣'),
          VoiceCueClass.funAck);
    });

    test('neutral fallback', () {
      expect(VoiceCueClassifier.classify('帮我倒一杯水'),
          VoiceCueClass.neutralLeadIn);
      expect(VoiceCueClassifier.classify('今天几号'),
          VoiceCueClass.neutralLeadIn);
      expect(VoiceCueClassifier.classify('我想吃火锅'),
          VoiceCueClass.neutralLeadIn);
    });

    test('farewell takes priority over question', () {
      // "不用了" is farewell, even if it could be a question.
      expect(VoiceCueClassifier.classify('不用了'),
          VoiceCueClass.farewell);
    });

    test('call state takes priority over neutral', () {
      expect(VoiceCueClassifier.classify('你能听到吗，我想问你个问题'),
          VoiceCueClass.callStateQuestion);
    });
  });
}