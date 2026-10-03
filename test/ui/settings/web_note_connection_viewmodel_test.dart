import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/notes/claude_web_note_feed_service.dart';
import 'package:memex/ui/settings/view_models/web_note_connection_viewmodel.dart';
import 'package:memex/utils/result.dart';

void main() {
  test('loads configuration, saves, reports unauthorized and disconnects',
      () async {
    final service = FakeWebNoteFeedService()
      ..config = const ClaudeWebNoteFeedConfig(
          baseUrl: 'https://synthetic.ts.net', token: 'iph_hidden', cursor: 7);
    final model = WebNoteConnectionViewModel(service);
    addTearDown(model.dispose);
    await model.load.execute();
    expect(model.baseUrl, 'https://synthetic.ts.net');
    expect(model.cursor, 7);
    expect(model.status, '已保存连接');
    await model.save
        .execute(const WebNoteConnectionInput('https://new.ts.net', 'iph_new'));
    expect(service.savedToken, 'iph_new');
    expect(model.baseUrl, 'https://new.ts.net');
    service.syncResult =
        const Ok(ClaudeWebNoteSyncReport(ClaudeWebNoteSyncStatus.unauthorized));
    await model.sync.execute();
    expect(model.status, '手机令牌已失效，请重新填写');
    await model.disconnect.execute();
    expect(service.clearCalls, 1);
    expect(service.config, isNull);
    expect(model.baseUrl, isNull);
    expect(model.cursor, 0);
    expect(model.status, '已断开连接');
  });

  for (final operation in ['load', 'sync', 'save', 'disconnect']) {
    test(
        '$operation completion after disposal neither notifies nor starts follow-up work',
        () async {
      final service = FakeWebNoteFeedService();
      final read = Completer<Result<ClaudeWebNoteFeedConfig?>>();
      final sync = Completer<Result<ClaudeWebNoteSyncReport>>();
      final write = Completer<Result<void>>();
      switch (operation) {
        case 'load':
          service.readFuture = read.future;
        case 'sync':
          service.syncFuture = sync.future;
        case 'save':
          service.configureFuture = write.future;
        case 'disconnect':
          service.clearFuture = write.future;
      }
      final model = WebNoteConnectionViewModel(service);
      var notifications = 0;
      model.addListener(() => notifications++);
      for (final command in [
        model.load,
        model.save,
        model.sync,
        model.disconnect
      ]) {
        command.addListener(() => notifications++);
      }
      final pending = switch (operation) {
        'load' => model.load.execute(),
        'sync' => model.sync.execute(),
        'save' => model.save.execute(
            const WebNoteConnectionInput('https://new.ts.net', 'iph_new')),
        _ => model.disconnect.execute(),
      };
      final countAtDisposal = notifications;
      model.dispose();
      switch (operation) {
        case 'load':
          read.complete(const Ok(ClaudeWebNoteFeedConfig(
              baseUrl: 'https://late.ts.net', token: 'iph_late')));
        case 'sync':
          sync.complete(const Ok(ClaudeWebNoteSyncReport(
              ClaudeWebNoteSyncStatus.synced,
              processed: 1)));
        case 'save' || 'disconnect':
          write.complete(const Ok.v());
      }
      await pending;
      expect(notifications, countAtDisposal);
      expect(model.baseUrl, isNull);
      expect(model.status, '尚未连接');
      expect(service.readCalls, operation == 'load' ? 1 : 0,
          reason: 'disposed save must not refresh configuration');
      final previousCalls = service.totalCalls;
      await model.load.execute();
      await model.sync.execute();
      await model.disconnect.execute();
      await model.save.execute(const WebNoteConnectionInput(
          'https://ignored.ts.net', 'iph_ignored'));
      expect(service.totalCalls, previousCalls);
      expect(service.disposeCalls, 0,
          reason: 'the provider owns the shared service');
    });
  }
}

/// Shared synthetic service for the ViewModel and route lifecycle tests.
class FakeWebNoteFeedService implements ClaudeWebNoteFeedService {
  ClaudeWebNoteFeedConfig? config;
  Future<Result<ClaudeWebNoteFeedConfig?>>? readFuture;
  Future<Result<ClaudeWebNoteSyncReport>>? syncFuture;
  Future<Result<void>>? configureFuture;
  Future<Result<void>>? clearFuture;
  Result<ClaudeWebNoteSyncReport> syncResult =
      const Ok(ClaudeWebNoteSyncReport(ClaudeWebNoteSyncStatus.synced));
  String? savedToken;
  int readCalls = 0;
  int syncCalls = 0;
  int configureCalls = 0;
  int clearCalls = 0;
  int disposeCalls = 0;
  int get totalCalls => readCalls + syncCalls + configureCalls + clearCalls;
  @override
  Future<Result<ClaudeWebNoteFeedConfig?>> readConfig() async {
    readCalls++;
    return await (readFuture ?? Future.value(Ok(config)));
  }

  @override
  Future<Result<void>> configure(
      {required String baseUrl, required String token}) async {
    configureCalls++;
    savedToken = token;
    config = ClaudeWebNoteFeedConfig(baseUrl: baseUrl, token: token);
    return await (configureFuture ?? Future.value(const Ok.v()));
  }

  @override
  Future<Result<ClaudeWebNoteSyncReport>> syncOnce() async {
    syncCalls++;
    return await (syncFuture ?? Future.value(syncResult));
  }

  @override
  Future<Result<void>> clearConnection() async {
    clearCalls++;
    config = null;
    return await (clearFuture ?? Future.value(const Ok.v()));
  }

  @override
  void dispose() {
    disposeCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
