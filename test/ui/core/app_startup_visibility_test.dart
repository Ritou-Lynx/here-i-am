import 'package:flutter/material.dart';
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

  testWidgets('opening splash renders the approved animated asset',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppOpeningSplash(statusText: '正在加载'),
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
  });
}
