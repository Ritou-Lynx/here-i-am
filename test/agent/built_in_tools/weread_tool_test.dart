import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/built_in_tools/weread_tool.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('weread_read is callable without arguments', () async {
    final tempRoot = await Directory.systemTemp.createTemp('weread_tool_test_');
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });
    await FileSystemService.init(tempRoot.path);
    final summaryFile = File(p.join(
      FileSystemService.instance.getUserSettingsPath('Lynx'),
      'external_data',
      'weread',
      'reading_summary.md',
    ));
    await summaryFile.parent.create(recursive: true);
    await summaryFile.writeAsString('# WeRead Reading Data\n最近在读测试书。');

    final tool = buildWereadTool(userId: 'Lynx');
    final result = await Function.apply(tool.executable!, []);

    expect(result, contains('最近在读测试书'));
  });
}
