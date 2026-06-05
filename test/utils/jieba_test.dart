import 'package:flutter_test/flutter_test.dart';
import 'package:memex/utils/jieba.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the dictionary in the background and segments text', () async {
    final segmenter = JiebaSegmenter.instance;
    segmenter.dispose();

    final loaded = await Future.wait([
      segmenter.ensureLoaded(),
      segmenter.ensureLoaded(),
    ]);

    expect(loaded, everyElement(isTrue));
    expect(segmenter.isLoaded, isTrue);
    expect(segmenter.cut('今天适合散步'), isNotEmpty);

    segmenter.dispose();
  });
}
