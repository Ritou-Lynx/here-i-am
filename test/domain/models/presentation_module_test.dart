import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/presentation_module.dart';

void main() {
  test('parses legacy prompt aliases without losing visible content', () {
    final module = PresentationModule.tryParse(jsonEncode({
      'blocks': [
        {
          'kind': 'number',
          'value': 83,
          'unit': '元',
          'caption': '总消费',
        },
        {
          'kind': 'table',
          'headers': ['项目', '金额', '备注'],
          'rows': [
            ['午餐', '83元', '两人'],
          ],
        },
        {
          'kind': 'progressBar',
          'value': 0.6,
          'label': '本周进度',
        },
      ],
    }));

    expect(module, isNotNull);
    final number = module!.blocks[0] as NumberBlock;
    final table = module.blocks[1] as TableBlock;
    final progress = module.blocks[2] as ProgressBarBlock;

    expect(number.note, '总消费');
    expect(table.rows.single.label, '午餐');
    expect(table.rows.single.value, '金额：83元 · 备注：两人');
    expect(progress.max, 1);
    expect(progress.fraction, 0.6);
  });
}
