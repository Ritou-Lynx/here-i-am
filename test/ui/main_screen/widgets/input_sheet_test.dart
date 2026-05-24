import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_asset_server.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/main_screen/widgets/input_sheet.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDataRoot;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'user_id': 'input-sheet-test'});
    await UserStorage.initL10n();

    testDataRoot = await Directory.systemTemp.createTemp('memex_input_sheet_');
    await FileSystemService.init(testDataRoot.path);
  });

  tearDownAll(() async {
    await LocalAssetServer.stopServer();
    if (await testDataRoot.exists()) {
      await testDataRoot.delete(recursive: true);
    }
  });

  Widget buildHost({InputData? initialData}) {
    var isOpen = true;
    var closeCount = 0;

    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            return Stack(
              children: [
                const Center(child: Text('Home content')),
                InputSheet(
                  isOpen: isOpen,
                  initialData: initialData ?? InputData(text: 'started note'),
                  onClose: () {
                    setState(() {
                      isOpen = false;
                      closeCount += 1;
                    });
                  },
                  onSubmit: (_) async => true,
                ),
                Text('close count: $closeCount'),
              ],
            );
          },
        ),
      ),
    );
  }

  testWidgets('Android back closes the open input sheet without popping home', (
    tester,
  ) async {
    await tester.pumpWidget(buildHost());
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Home content'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'typed before back');
    await tester.pump();

    final handled = await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 50));

    expect(handled, isTrue);
    expect(find.text('Home content'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('close count: 1'), findsOneWidget);
  });

  testWidgets('keeps the input and send controls visible with media attached', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final imageFile = File('${testDataRoot.path}/input_sheet_preview.png');
    await imageFile.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lDRT2wAAAABJRU5ErkJggg==',
      ),
    );

    await tester.pumpWidget(
      buildHost(
        initialData: InputData(
          text: '#tag started note',
          images: [XFile(imageFile.path)],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(UserStorage.l10n.recordLabel), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
  });
}
