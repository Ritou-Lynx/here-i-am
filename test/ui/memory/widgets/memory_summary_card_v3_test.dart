import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/domain/models/presentation_module.dart';
import 'package:memex/ui/companion/widgets/companion_review_screen.dart';
import 'package:memex/ui/memory/widgets/memory_summary_card_v3.dart';

void main() {
  test('memory review timestamp always uses one absolute Chinese format', () {
    final currentYear = DateTime(2026, 8, 1);
    expect(
      formatMemoryReviewTimestamp(
        DateTime(2026, 7, 30, 21, 14).millisecondsSinceEpoch,
        now: currentYear,
      ),
      '7月30日 21:14',
    );
    expect(
      formatMemoryReviewTimestamp(
        DateTime(2025, 7, 30, 21, 14).millisecondsSinceEpoch,
        now: currentYear,
      ),
      '2025年7月30日 21:14',
    );
  });

  testWidgets('spring rain review card keeps metadata inside the card', (
    tester,
  ) async {
    var tapCount = 0;
    final card = MemoryCardViewData(
      id: 'card-1',
      type: 'event',
      title: 'system title',
      dropletLabel: '雨声',
      presentationModule: '',
      retrievalText: '窗外开始下雨了。',
      valence: 0.2,
      arousal: 0.3,
      createdAt: 1,
      updatedAt: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemorySummaryCardV3(
            card: card,
            variant: MemorySummaryCardVariant.springRainReview,
            metaLabel: '8月1日 18:02',
            categoryLabel: card.typeLabel,
            pressFeedback: true,
            onTap: () => tapCount += 1,
          ),
        ),
      ),
    );

    expect(find.text('8月1日 18:02'), findsOneWidget);
    expect(find.text('事件'), findsOneWidget);
    expect(find.text('雨声'), findsOneWidget);
    expect(find.text('窗外开始下雨了。'), findsOneWidget);

    await tester.tap(find.text('雨声'));
    await tester.pumpAndSettle();
    expect(tapCount, 1);
  });

  testWidgets('renders every supported presentation module', (tester) async {
    const presentation = PresentationModule(
      title: '睡眠记录',
      subjectRef: '身体 · 最近一周',
      statusLabel: '需复核',
      blocks: [
        TextBlock(text: '昨晚比前几天睡得安稳。', emphases: ['睡得安稳']),
        QuoteBlock(text: '醒来时没有那么累。', context: '8月1日早晨'),
        NumberBlock(value: '6.8', unit: '小时', note: '昨晚睡眠'),
        TableBlock(rows: [
          TableRowData(label: '入睡', value: '00:36'),
          TableRowData(label: '醒来', value: '07:24'),
        ]),
        SparklineBlock(points: [6.1, 7.2, 5.8, 6.8], caption: '最近四天睡眠时长'),
        MediaBlock(
          assetPath: 'audio/sleep-note.m4a',
          kind: 'audio',
          caption: '睡前语音记录',
        ),
        LinkAttachmentBlock(
          url: 'https://example.com/sleep',
          title: '睡眠记录参考',
          source: 'web',
        ),
        ProgressBarBlock(value: 3, max: 5, unit: '天', label: '本周早睡'),
      ],
    );
    final card = MemoryCardViewData(
      id: 'card-modules',
      type: 'fact',
      title: 'hidden system title',
      dropletLabel: '睡眠',
      presentationModule: presentation.toJsonString(),
      retrievalText: 'fallback',
      valence: 0.1,
      arousal: 0.2,
      createdAt: 1,
      updatedAt: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MemorySummaryCardV3(
              card: card,
              variant: MemorySummaryCardVariant.springRainReview,
              metaLabel: '8月1日 07:24',
              categoryLabel: card.typeLabel,
            ),
          ),
        ),
      ),
    );

    expect(find.text('睡眠记录'), findsOneWidget);
    expect(find.text('身体 · 最近一周'), findsOneWidget);
    expect(find.text('需复核'), findsOneWidget);
    expect(
      find.text('昨晚比前几天睡得安稳。', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('"醒来时没有那么累。"'), findsOneWidget);
    expect(find.text('6.8', findRichText: true), findsOneWidget);
    expect(find.text('00:36'), findsOneWidget);
    expect(find.text('最近四天睡眠时长'), findsOneWidget);
    expect(find.text('音频'), findsOneWidget);
    expect(find.text('睡前语音记录'), findsOneWidget);
    expect(find.text('睡眠记录参考'), findsOneWidget);
    expect(find.text('本周早睡'), findsOneWidget);
    expect(find.text('3/5 天'), findsOneWidget);
  });
}
