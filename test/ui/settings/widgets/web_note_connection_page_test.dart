import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/notes/claude_web_note_feed_service.dart';
import 'package:memex/ui/settings/widgets/web_note_connection_page.dart';
import 'package:memex/utils/result.dart';
import '../web_note_connection_viewmodel_test.dart' show FakeWebNoteFeedService;

const _urlKey = ValueKey('web_notes_url');
const _tokenKey = ValueKey('web_notes_token');
const _saveKey = ValueKey('web_notes_save');
const _syncKey = ValueKey('web_notes_sync');
const _disconnectKey = ValueKey('web_notes_disconnect');
const _config = ClaudeWebNoteFeedConfig(
    baseUrl: 'https://synthetic.ts.net', token: 'iph_saved_secret', cursor: 7);

Future<void> _open(WidgetTester tester, FakeWebNoteFeedService service) =>
    tester
        .pumpWidget(MaterialApp(home: WebNoteConnectionPage(service: service)));

void main() {
  testWidgets(
      'leaving while loading ignores completion without disposed notifications',
      (tester) async {
    final pending = Completer<Result<ClaudeWebNoteFeedConfig?>>();
    final service = FakeWebNoteFeedService()..readFuture = pending.future;
    await _open(tester, service);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(const Ok(_config));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(service.disposeCalls, 0);
  });

  testWidgets('leaving during sync permits the shared import to finish safely',
      (tester) async {
    final pending = Completer<Result<ClaudeWebNoteSyncReport>>();
    final service = FakeWebNoteFeedService()
      ..config = _config
      ..syncFuture = pending.future;
    await _open(tester, service);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_syncKey));
    await tester.pump();
    expect(service.syncCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(const Ok(
        ClaudeWebNoteSyncReport(ClaudeWebNoteSyncStatus.synced, processed: 1)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(service.disposeCalls, 0);
  });

  testWidgets(
      'saved token is never restored to the field, 401 prompts replacement',
      (tester) async {
    final service = FakeWebNoteFeedService()
      ..config = _config
      ..syncResult = const Ok(
          ClaudeWebNoteSyncReport(ClaudeWebNoteSyncStatus.unauthorized));
    await _open(tester, service);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(_urlKey)).controller!.text,
        _config.baseUrl);
    final tokenField = tester.widget<TextField>(find.byKey(_tokenKey));
    expect(tokenField.controller!.text, isEmpty);
    expect(tokenField.obscureText, isTrue);
    expect(find.text('iph_saved_secret'), findsNothing);
    await tester.tap(find.byKey(_syncKey));
    await tester.pumpAndSettle();
    expect(find.text('手机令牌已失效，请重新填写'), findsOneWidget);
  });

  testWidgets(
      'save clears the pasted token and syncs, disconnect clears connection',
      (tester) async {
    final service = FakeWebNoteFeedService();
    await _open(tester, service);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_urlKey), 'https://configured.ts.net');
    await tester.enterText(find.byKey(_tokenKey), 'iph_pasted_secret');
    await tester.tap(find.byKey(_saveKey));
    await tester.pumpAndSettle();
    expect(service.config!.baseUrl, 'https://configured.ts.net');
    expect(service.savedToken, 'iph_pasted_secret');
    expect(service.syncCalls, 1);
    expect(tester.widget<TextField>(find.byKey(_tokenKey)).controller!.text,
        isEmpty);
    expect(find.text('iph_pasted_secret'), findsNothing);
    await tester.ensureVisible(find.byKey(_disconnectKey));
    await tester.tap(find.byKey(_disconnectKey));
    await tester.pumpAndSettle();
    expect(service.config, isNull);
    expect(find.text('已断开连接'), findsOneWidget);
    expect(find.byKey(_syncKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving during save does not start a post-save sync',
      (tester) async {
    final pending = Completer<Result<void>>();
    final service = FakeWebNoteFeedService()..configureFuture = pending.future;
    await _open(tester, service);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_urlKey), 'https://configured.ts.net');
    await tester.enterText(find.byKey(_tokenKey), 'iph_pasted_secret');
    await tester.tap(find.byKey(_saveKey));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(_tokenKey)).controller!.text,
        isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(const Ok.v());
    await tester.pumpAndSettle();
    expect(service.syncCalls, 0);
    expect(tester.takeException(), isNull);
  });
}
