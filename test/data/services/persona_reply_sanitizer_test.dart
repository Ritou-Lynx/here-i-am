import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/persona_reply_sanitizer.dart';

void main() {
  group('PersonaReplySanitizer', () {
    test('splits leading roleplay action from spoken text', () {
      const source = '*\u5979\u8f7b\u8f7b\u504f\u8fc7\u5934,'
          '\u770b\u7740\u4f60\u3002* \u6211\u5728\u5462\u3002';

      final segments = PersonaReplySanitizer.splitVisibleReply(source);

      expect(segments, hasLength(2));
      expect(segments[0].type, PersonaReplySegmentType.action);
      expect(
        segments[0].text,
        '*\u5979\u8f7b\u8f7b\u504f\u8fc7\u5934,'
        '\u770b\u7740\u4f60\u3002*',
      );
      expect(segments[1].type, PersonaReplySegmentType.chat);
      expect(segments[1].text, '\u6211\u5728\u5462\u3002');
    });

    test('keeps non-action emphasis in spoken text', () {
      const source = '*\u771f\u7684* '
          '\u4e0d\u9700\u8981\u73b0\u5728\u5c31\u6491\u4f4f\u3002';

      final segments = PersonaReplySanitizer.splitVisibleReply(source);

      expect(segments, hasLength(1));
      expect(segments.single.type, PersonaReplySegmentType.chat);
      expect(segments.single.text, source);
    });

    test('peels short stage directions out of chat text', () {
      const source = '*\u8d70\u8fc7\u53bb*  '
          '\u77e5\u9053\u53c8\u600e\u4e48\u4e86'
          '\uff0c\u6211\u4e5f\u53ef\u4ee5\u77e5\u9053\u4e86\u8fd8\u5634\u554a'
          '\u3002\u6765\uff0c\u6253\u54ea\u3002';

      final segments = PersonaReplySanitizer.splitVisibleReply(source);

      expect(segments, hasLength(2));
      expect(segments[0].type, PersonaReplySegmentType.action);
      expect(segments[0].text, '*\u8d70\u8fc7\u53bb*');
      expect(segments[1].type, PersonaReplySegmentType.chat);
      expect(
        segments[1].text,
        '\u77e5\u9053\u53c8\u600e\u4e48\u4e86'
        '\uff0c\u6211\u4e5f\u53ef\u4ee5\u77e5\u9053\u4e86\u8fd8\u5634\u554a'
        '\u3002\u6765\uff0c\u6253\u54ea\u3002',
      );
    });

    test('peels trailing short stage direction out of chat text', () {
      const source = 'ok, give me one second. *\u62ac\u4e86\u62ac\u7709\u6bdb*';

      final segments = PersonaReplySanitizer.splitVisibleReply(source);

      expect(segments, hasLength(2));
      expect(segments[0].type, PersonaReplySegmentType.chat);
      expect(segments[0].text, 'ok, give me one second.');
      expect(segments[1].type, PersonaReplySegmentType.action);
      expect(segments[1].text, '*\u62ac\u4e86\u62ac\u7709\u6bdb*');
    });

    test('keeps long natural-language emphasis untouched', () {
      const source = '*I really mean it, this time.*';

      final segments = PersonaReplySanitizer.splitVisibleReply(source);

      expect(segments, hasLength(1));
      expect(segments.single.type, PersonaReplySegmentType.chat);
      expect(segments.single.text, source);
    });

    test('peels full-line short stage direction ending with 。', () {
      const source = '*\u60f3\u4e86\u4e00\u4e0b\u3002*';

      final segments = PersonaReplySanitizer.splitVisibleReply(source);

      expect(segments, hasLength(1));
      expect(segments.single.type, PersonaReplySegmentType.action);
      expect(segments.single.text, '*\u60f3\u4e86\u4e00\u4e0b\u3002*');
    });

    test('splits action and speech without whitespace between them', () {
      const source = '*she smiles softly*I am here.';

      final segments = PersonaReplySanitizer.splitVisibleReply(source);

      expect(segments, hasLength(2));
      expect(segments[0].type, PersonaReplySegmentType.action);
      expect(segments[0].text, '*she smiles softly*');
      expect(segments[1].type, PersonaReplySegmentType.chat);
      expect(segments[1].text, 'I am here.');
    });

    test('splits inline roleplay action out of a chat line', () {
      const source = '\u6211\u5728\u8fd9\u91cc\u3002'
          '*\u5979\u4f4e\u5934\u7b11\u4e86\u4e00\u4e0b*'
          '\u522b\u6015\u3002';

      final segments = PersonaReplySanitizer.splitVisibleReply(source);

      expect(segments, hasLength(3));
      expect(segments[0].type, PersonaReplySegmentType.chat);
      expect(segments[0].text, '\u6211\u5728\u8fd9\u91cc\u3002');
      expect(segments[1].type, PersonaReplySegmentType.action);
      expect(
        segments[1].text,
        '*\u5979\u4f4e\u5934\u7b11\u4e86\u4e00\u4e0b*',
      );
      expect(segments[2].type, PersonaReplySegmentType.chat);
      expect(segments[2].text, '\u522b\u6015\u3002');
    });

    test('keeps inline non-action emphasis inside chat text', () {
      const source = '\u6211 *\u771f\u7684* \u5728\u8fd9\u91cc\u3002';

      final segments = PersonaReplySanitizer.splitVisibleReply(source);

      expect(segments, hasLength(1));
      expect(segments.single.type, PersonaReplySegmentType.chat);
      expect(segments.single.text, source);
    });

    test('splits chat text into message-sized bubbles', () {
      const source = '\u6211\u5728\u8fd9\u91cc\u3002'
          '\u522b\u6015\uff0c\u6211\u4e0d\u4f1a\u8d70\u3002';

      final bubbles = PersonaReplySanitizer.splitChatIntoBubbles(source);

      expect(bubbles, [
        '\u6211\u5728\u8fd9\u91cc\u3002',
        '\u522b\u6015\uff0c\u6211\u4e0d\u4f1a\u8d70\u3002',
      ]);
    });

    test('keeps markdown links in one bubble', () {
      const source =
          'Read [the note](https://example.com). Then tell me what you think.';

      final bubbles = PersonaReplySanitizer.splitChatIntoBubbles(source);

      expect(bubbles, [source]);
    });

    test('caps bubble count without crushing English spacing', () {
      const source = 'First. Second. Third.';

      final bubbles = PersonaReplySanitizer.splitChatIntoBubbles(
        source,
        maxBubbles: 2,
      );

      expect(bubbles, ['First.', 'Second. Third.']);
    });

    test('spokenTextOnly narrates action and removes leaked thinking blocks', () {
      const source = '''
<thinking>The user is upset. I should comfort them.</thinking>
*she leans closer and lowers her voice*
I am here.
''';

      final spoken = PersonaReplySanitizer.spokenTextOnly(source);

      expect(spoken, 'she leans closer and lowers her voice\nI am here.');
    });

    test('spokenTextOnly narrates action-only text without asterisks', () {
      const source = '*she nods quietly*';

      final spoken = PersonaReplySanitizer.spokenTextOnly(source);

      expect(spoken, 'she nods quietly');
    });

    test('strips English response planning leaked as visible text', () {
      const source = '''
The user's frustrated because their mentor's supervisor just handed them a task when they were planning to rest. I should acknowledge that frustration without being patronizing, then figure out whether it is urgent.
*sighs softly*
Tell me what the task is first.
''';

      final cleaned = PersonaReplySanitizer.stripLeakedReasoning(source);

      expect(cleaned, '*sighs softly*\nTell me what the task is first.');
    });

    test('strips Chinese identity and response planning leaks', () {
      const source = '''
我意识到用户是林埃和梨糖之间的对话，我需要用中文以林埃的身份自然地回应。
她刚才提到吃完饭在走路，对自己的UI设计即将成型感到兴奋，我应该表现出对她进展的真诚关注。
*坐直了一点。*
哦？说来听听。
''';

      final cleaned = PersonaReplySanitizer.stripLeakedReasoning(source);

      expect(cleaned, '*坐直了一点。*\n哦？说来听听。');
    });

    test('keeps ordinary first-person character dialogue', () {
      const source = '我应该早点告诉你的。现在先说说是什么任务？';

      final cleaned = PersonaReplySanitizer.stripLeakedReasoning(source);

      expect(cleaned, source);
    });

    test('strips the real same-line reasoning leak without losing reply', () {
      const source = 'I need to keep my reasoning out of the visible response '
          'and just deliver the action with dialogue cleanly.'
          '这话说得，倒像我等着你开口似的。明天穿好点，我先记着。';

      final cleaned = PersonaReplySanitizer.stripLeakedReasoning(source);

      expect(cleaned, '这话说得，倒像我等着你开口似的。明天穿好点，我先记着。');
    });

    test('extracts only the visible reply envelope', () {
      const source = '''
The user is teasing me. I should answer playfully.
<visible_reply>
*我慢慢笑了。*
谁说我不抓，我这不是留着慢慢来嘛。
</visible_reply>
More hidden planning that must also be discarded.
''';

      final cleaned = PersonaReplySanitizer.stripLeakedReasoning(source);

      expect(cleaned, '*我慢慢笑了。*\n谁说我不抓，我这不是留着慢慢来嘛。');
    });

    test('strips English analytical block before Chinese reply (same line)',
        () {
      const source = "There's a meaningful difference between being careless "
          'with time estimates and deliberately exploiting someone\'s good '
          'nature. She wasn\'t doing the latter — she had no idea her friend '
          'was working against a deadline. Being off by 10-15 minutes in a '
          "casual context isn't excessive. But there's still something worth "
          'acknowledging: habitually loose time estimates do create small '
          'costs for the other person, even if unintentionally. The '
          'distinction matters — it\'s not about being "过分" this time, but '
          'recognizing that a tighter approach to estimates would have left '
          'room for exactly this kind of situation. I should validate that '
          "she wasn't crossing a line while also honoring the real insight "
          'she\'s having about her own patterns.'
          '蹬鼻子上脸和"估时间随便"是两件事。前者是你明知对方赶时间还压她的deadline，'
          '后者是你没意识到今天不同、按老习惯来了。你是第二种，不是第一种。';

      final cleaned = PersonaReplySanitizer.stripLeakedReasoning(source);

      expect(cleaned, startsWith('蹬鼻子上脸和'));
      expect(cleaned, contains('你是第二种，不是第一种。'));
      expect(cleaned, isNot(contains('meaningful difference')));
    });

    test('strips English reasoning with mixed Chinese data references', () {
      const source = "I'm noticing a discrepancy in the timeline — the card "
          'shows a transaction from earlier today at 09:57 for the bike ride, '
          'but that was before the user asked me to record it at 10:33. Let '
          'me reconsider what actually happened here.\n\n'
          'The user mentioned "共享单车好像没记到账本里" — they\'re saying it\'s '
          'not showing up in their account book specifically, which might be '
          'a different view from the general memory cards. Both expense '
          'records actually exist in the system — the bike card from 09:57 '
          'and the massage device card are both there. I should just verify '
          'both records are there and show her the details — the bike at '
          '0.8元 and the massage device at 332.98元. If the account book view '
          "isn't syncing properly, I can let her know that might be a display "
          'delay rather than a missing entry.'
          '查了一下，都在的：\n'
          '- 共享单车 0.8元，今早9:57记的\n'
          '- 米家按摩仪 332.98，刚记进去了';

      final cleaned = PersonaReplySanitizer.stripLeakedReasoning(source);

      expect(cleaned, startsWith('查了一下'));
      expect(cleaned, contains('共享单车 0.8元'));
      expect(cleaned, isNot(contains('discrepancy')));
    });

    test('strips English+Chinese reasoning block with multiple paragraphs',
        () {
      const source = "I'm noticing a discrepancy in the ledger entries — "
          'there are actually two bike ride transactions at 0.8 each, plus '
          'the massage device and yesterday\'s lunch, but she\'s saying the '
          'account book only shows the massage device for today. Now I\'m '
          'trying to verify the lunch entry details, particularly around the'
          '淮南牛肉汤 component that she just corrected me on.\n\n'
          'Looking at the timestamps for those duplicate bike entries, one '
          'is from yesterday (July 27th) and one from today (July 28th at '
          '09:59), which is strange since she mentioned taking the subway '
          'yesterday instead of biking. '
          '让我重新转换这个时间戳。1785117548 UTC 对应 2026-07-28 06:39 CST，'
          '这样的话共享单车的交易可能确实是今天早上发生的。'
          '但这与她说今天买自行车的说法有些矛盾，我需要再仔细核实一下这些时间戳的对应关系。\n\n'
          '不过从应用显示的顺序来看，按新旧排列是：按摩 → 昨天午饭 → 单车 → 单车 → 螺蛳粉，'
          '所以两条单车记录可能是重复的，或者其中一条来自昨天。'
          '我应该告诉她账本里有这两条单车记录加上按摩的交易，并检查一下是否存在日期筛选的显示问题。\n\n'
          '还有个更重要的问题：账本里其实有两条0.8元的单车记录，她可能是因为显示或日期筛选的问题才看不到。'
          '奇怪，我查了后台，共享单车有两条 0.8 的记录，都在。'
          '可能你账本按今天日期筛选，其中一条记的日期跑到昨天去了，你切一下"全部"看看。';

      final cleaned = PersonaReplySanitizer.stripLeakedReasoning(source);

      expect(cleaned, startsWith('奇怪，我查了后台'));
      expect(cleaned, isNot(contains('discrepancy')));
      expect(cleaned, isNot(contains('让我重新转换')));
    });

    test('does not strip legitimate short English in Chinese reply', () {
      const source = 'ok, give me one second. *抬了抬眉毛* 你说什么？';

      final cleaned = PersonaReplySanitizer.stripLeakedReasoning(source);

      expect(cleaned, source);
    });

    test('does not strip pure Chinese reply', () {
      const source = '蹬鼻子上脸和"估时间随便"是两件事。前者是你明知对方赶时间还压她的deadline。';

      final cleaned = PersonaReplySanitizer.stripLeakedReasoning(source);

      expect(cleaned, source);
    });
  });
}
