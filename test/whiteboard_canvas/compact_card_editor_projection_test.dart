import 'package:flutter_test/flutter_test.dart';

import 'package:memex/ui/whiteboard_canvas/widgets/compact_card_editor.dart';

void main() {
  test('single inline value projects first line to title and remainder to body',
      () {
    final projection = InlineCardTextProjection.fromText(
      '第一行标题\n正文一\n正文二',
    );

    expect(projection.title, '第一行标题');
    expect(projection.body, '正文一\n正文二');
    expect(
      InlineCardTextProjection.compose(
        title: projection.title,
        body: projection.body,
      ),
      '第一行标题\n正文一\n正文二',
    );
  });

  test('a single line stays a title and empty card stays empty', () {
    final titleOnly = InlineCardTextProjection.fromText('只有标题');
    final empty = InlineCardTextProjection.fromText('');

    expect(titleOnly.title, '只有标题');
    expect(titleOnly.body, isEmpty);
    expect(empty.title, isEmpty);
    expect(empty.body, isEmpty);
    expect(
      InlineCardTextProjection.compose(title: '', body: ''),
      isEmpty,
    );
  });
}
