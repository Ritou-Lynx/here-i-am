import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/whiteboard/editor/unsaved_exit_guard.dart';

void main() {
  group('confirmUnsavedExit', () {
    testWidgets('returns discard immediately when nothing is unsaved',
        (tester) async {
      var onSaveCalled = false;
      late Future<UnsavedExitChoice> pending;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    pending = confirmUnsavedExit(
                      ctx,
                      hasUnsavedChanges: false,
                      onSave: () async => onSaveCalled = true,
                    );
                  },
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      final result = await pending;
      expect(result, equals(UnsavedExitChoice.discard));
      expect(onSaveCalled, isFalse);
    });

    testWidgets('cancel keeps the user in the editor', (tester) async {
      var onSaveCalled = false;
      late Future<UnsavedExitChoice> pending;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    pending = confirmUnsavedExit(
                      ctx,
                      hasUnsavedChanges: true,
                      onSave: () async => onSaveCalled = true,
                    );
                  },
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('尚未保存'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      final result = await pending;
      expect(result, equals(UnsavedExitChoice.cancel));
      expect(onSaveCalled, isFalse);
    });

    testWidgets('discard does not call onSave', (tester) async {
      var onSaveCalled = false;
      late Future<UnsavedExitChoice> pending;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    pending = confirmUnsavedExit(
                      ctx,
                      hasUnsavedChanges: true,
                      onSave: () async => onSaveCalled = true,
                    );
                  },
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃'));
      await tester.pumpAndSettle();
      final result = await pending;
      expect(result, equals(UnsavedExitChoice.discard));
      expect(onSaveCalled, isFalse);
    });

    testWidgets('save calls onSave then returns save', (tester) async {
      var onSaveCalled = false;
      late Future<UnsavedExitChoice> pending;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    pending = confirmUnsavedExit(
                      ctx,
                      hasUnsavedChanges: true,
                      onSave: () async => onSaveCalled = true,
                    );
                  },
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存并退出'));
      await tester.pumpAndSettle();
      final result = await pending;
      expect(result, equals(UnsavedExitChoice.save));
      expect(onSaveCalled, isTrue);
    });
  });
}