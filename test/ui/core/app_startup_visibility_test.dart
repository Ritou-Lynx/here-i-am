import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/core/app_startup_visibility.dart';
import 'package:memex/ui/core/widgets/app_opening_splash.dart';

void main() {
  setUp(AppStartupVisibilityController.markLoading);

  test('app chrome stays disabled until startup is interactive', () {
    expect(
      AppStartupVisibilityController.isAppInteractive.value,
      isFalse,
    );

    AppStartupVisibilityController.markInteractive();
    expect(
      AppStartupVisibilityController.isAppInteractive.value,
      isTrue,
    );

    AppStartupVisibilityController.markLoading();
    expect(
      AppStartupVisibilityController.isAppInteractive.value,
      isFalse,
    );
  });

  test('opening splash loop video is packaged in assets', () async {
    final video = await rootBundle.load(AppOpeningSplash.videoAssetPath);
    final poster = await rootBundle.load(AppOpeningSplash.assetPath);
    final source = await rootBundle.load(AppOpeningSplash.sourceAssetPath);

    expect(AppOpeningSplash.videoAssetPath, endsWith('.mp4'));
    expect(AppOpeningSplash.assetPath, endsWith('_poster.png'));
    expect(AppOpeningSplash.sourceAssetPath, endsWith('.webp'));
    expect(video.lengthInBytes, greaterThan(100000));
    expect(poster.lengthInBytes, greaterThan(100000));
    expect(source.lengthInBytes, greaterThan(100000));
  });

  testWidgets('opening splash renders the approved animated asset',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppOpeningSplash(statusText: '正在加载', playVideo: false),
      ),
    );

    expect(
      find.byKey(const ValueKey('app_opening_animation')),
      findsOneWidget,
    );
    expect(find.text('正在加载'), findsOneWidget);

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('app_opening_animation')),
    );
    final provider = image.image as AssetImage;
    expect(provider.assetName, AppOpeningSplash.assetPath);
    expect(image.fit, BoxFit.contain);
    expect(image.alignment, Alignment.bottomCenter);
  });
}
