import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/ui/desktop/desktop_workspace_shell.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/desktop/widgets/desktop_brand_mark.dart';

void main() {
  Future<void> setViewport(
    WidgetTester tester,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget standardShell({String activePath = '/cards'}) {
    return MaterialApp(
      home: DesktopWorkspaceShell(
        title: '卡片库',
        meta: '共享地基',
        activePath: activePath,
        child: const SizedBox.expand(
          key: ValueKey('foundation_test_content'),
        ),
      ),
    );
  }

  testWidgets('standard shell uses scoped Lieflat Palm canvas and 148px nav',
      (tester) async {
    await setViewport(tester, const Size(1440, 900));
    await tester.pumpWidget(standardShell());
    await tester.pump();

    expect(
        find.byKey(const ValueKey('desktop_standard_shell')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop_page_title')), findsOneWidget);
    expect(find.text('卡片库'), findsWidgets);
    expect(
      tester.getSize(find.byKey(const ValueKey('desktop_sidebar'))).width,
      DesktopWorkspaceTokens.sidebarExpandedWidth,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('desktop_sidebar_handle')))
          .width,
      DesktopWorkspaceTokens.sidebarHandleWidth,
    );
    final scaffold = tester.widget<Scaffold>(
      find.byKey(const ValueKey('desktop_standard_shell')),
    );
    expect(scaffold.backgroundColor, const Color(0xFFF0EFEB));
  });

  testWidgets('sidebar handle stays shadow-free while content exits',
      (tester) async {
    await setViewport(tester, const Size(1280, 720));
    await tester.pumpWidget(standardShell());
    await tester.pump();

    final before = tester
        .getSize(find.byKey(const ValueKey('desktop_workspace_content')))
        .width;
    expect(
      find.byKey(const ValueKey('desktop_sidebar_paper_seam')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('desktop_sidebar_toggle')));
    await tester.pump();

    expect(find.byKey(const ValueKey('desktop_sidebar')), findsNothing);
    expect(find.byKey(const ValueKey('desktop_brand_mark')), findsNothing);
    expect(
      find.byKey(const ValueKey('desktop_sidebar_paper_seam')),
      findsNothing,
    );
    expect(
        find.byKey(const ValueKey('desktop_sidebar_handle')), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('desktop_sidebar_handle')))
          .width,
      DesktopWorkspaceTokens.sidebarHandleWidth,
    );
    final after = tester
        .getSize(find.byKey(const ValueKey('desktop_workspace_content')))
        .width;
    expect(
      after - before,
      DesktopWorkspaceTokens.sidebarExpandedWidth,
    );

    await tester.tap(find.byKey(const ValueKey('desktop_sidebar_toggle')));
    await tester.pump();
    expect(find.byKey(const ValueKey('desktop_sidebar')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktop_sidebar_paper_seam')),
      findsNothing,
    );
  });

  testWidgets('nested card route keeps the card library nav item active',
      (tester) async {
    await setViewport(tester, const Size(1280, 720));
    await tester.pumpWidget(standardShell(activePath: '/cards/card_abc'));
    await tester.pump();

    final semantics = tester.widget<Semantics>(
      find.byKey(const ValueKey('desktop_sidebar_nav_卡片库')),
    );
    expect(semantics.properties.selected, isTrue);
    final home = tester.widget<Semantics>(
      find.byKey(const ValueKey('desktop_sidebar_nav_首页')),
    );
    expect(home.properties.selected, isFalse);
  });

  testWidgets('link import keeps the card library nav item active',
      (tester) async {
    await setViewport(tester, const Size(1280, 720));
    await tester.pumpWidget(standardShell(activePath: '/import'));
    await tester.pump();

    final cards = tester.widget<Semantics>(
      find.byKey(const ValueKey('desktop_sidebar_nav_卡片库')),
    );
    expect(cards.properties.selected, isTrue);
    final home = tester.widget<Semantics>(
      find.byKey(const ValueKey('desktop_sidebar_nav_首页')),
    );
    expect(home.properties.selected, isFalse);
  });

  testWidgets('immersive shell renders no persistent nav, handle, or top bar',
      (tester) async {
    await setViewport(tester, const Size(1280, 720));
    await tester.pumpWidget(
      const MaterialApp(
        home: DesktopWorkspaceShell(
          title: '沉浸画布',
          mode: DesktopWorkspaceMode.immersive,
          child: SizedBox.expand(
            key: ValueKey('immersive_test_content'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
        find.byKey(const ValueKey('desktop_immersive_shell')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop_sidebar')), findsNothing);
    expect(find.byKey(const ValueKey('desktop_sidebar_handle')), findsNothing);
    expect(find.byKey(const ValueKey('desktop_page_title')), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('immersive_test_content'))),
      const Size(1280, 720),
    );
  });

  testWidgets('1280x720 and 1440x900 standard layouts stay overflow-free',
      (tester) async {
    for (final size in const [Size(1280, 720), Size(1440, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(standardShell());
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'viewport $size');
      expect(
        tester.getSize(find.byKey(const ValueKey('desktop_standard_shell'))),
        size,
      );
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('official plant-i asset is bundled and decodes', (tester) async {
    expect(
      DesktopBrandMark.assetPath,
      'assets/branding/hereiam_v3_logo/'
      'logo_foreground_ink_green_1024.png',
    );
    final bytes = await rootBundle.load(DesktopBrandMark.assetPath);
    expect(bytes.lengthInBytes, greaterThan(0));

    await tester.pumpWidget(
      const MaterialApp(home: Center(child: DesktopBrandMark())),
    );
    await precacheImage(
      const AssetImage(DesktopBrandMark.assetPath),
      tester.element(find.byKey(const ValueKey('desktop_brand_mark'))),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('desktop_brand_asset')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
