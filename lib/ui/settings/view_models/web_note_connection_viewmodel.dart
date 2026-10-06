import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:memex/data/memory_v3/notes/claude_web_note_feed_service.dart';
import 'package:memex/utils/command.dart';
import 'package:memex/utils/result.dart';

class WebNoteConnectionInput {
  const WebNoteConnectionInput(this.baseUrl, this.token);
  final String baseUrl;
  final String token;
}

class WebNoteConnectionViewModel extends ChangeNotifier
    with _DisposeAwareNotifier {
  WebNoteConnectionViewModel(this._service) {
    load = _PageCommand0(_load);
    save = _PageCommand1(_save);
    sync = _PageCommand0(_sync);
    disconnect = _PageCommand0(_disconnect);
  }
  final ClaudeWebNoteFeedService _service;
  late final Command0<void> load;
  late final Command1<void, WebNoteConnectionInput> save;
  late final Command0<ClaudeWebNoteSyncReport> sync;
  late final Command0<void> disconnect;
  String? baseUrl;
  int cursor = 0;
  String status = '尚未连接';

  Future<Result<void>> _load() async {
    final result = await _service.readConfig();
    if (_disposed) return const Ok.v();
    return result.when(
        onOk: (config) {
          baseUrl = config?.baseUrl;
          cursor = config?.cursor ?? 0;
          status = config == null ? '尚未连接' : '已保存连接';
          notifyListeners();
          return const Ok.v();
        },
        onError: (error, stack) => Error<void>(error, stack));
  }

  Future<Result<void>> _save(WebNoteConnectionInput input) async {
    final result =
        await _service.configure(baseUrl: input.baseUrl, token: input.token);
    if (_disposed) return result;
    return switch (result) {
      Ok<void>() => await _load(),
      Error<void>() => result,
    };
  }

  Future<Result<ClaudeWebNoteSyncReport>> _sync() async {
    final result = await _service.syncOnce();
    if (_disposed) return result;
    switch (result) {
      case Ok(:final value):
        cursor = value.cursor;
        status = switch (value.status) {
          ClaudeWebNoteSyncStatus.notConfigured => '请先保存地址和手机令牌',
          ClaudeWebNoteSyncStatus.unauthorized => '手机令牌已失效，请重新填写',
          ClaudeWebNoteSyncStatus.synced => value.pending > 0
              ? '已同步；${value.pending} 项保留原卡，等待确认'
              : value.processed == 0
                  ? '已同步，暂无新记录'
                  : '已同步 ${value.processed} 条记录',
        };
      case Error(:final error):
        status = switch (error) {
          DomainFailure(code: 'capture_owner_mismatch') => '新通道已接管，旧网页通道已停止拉取',
          DomainFailure(code: 'capture_consumer_busy') => '另一同步正在处理，请稍后再试',
          DomainFailure(code: 'capture_consumer_fenced') =>
            '同步所有权已移交，本次未推进同步进度',
          _ => '同步暂未完成，稍后会重试',
        };
    }
    notifyListeners();
    return result;
  }

  Future<Result<void>> _disconnect() async {
    final result = await _service.clearConnection();
    if (_disposed) return result;
    if (result is Ok<void>) {
      baseUrl = null;
      cursor = 0;
      status = '已断开连接';
      notifyListeners();
    }
    return result;
  }

  @override
  void dispose() {
    load.dispose();
    save.dispose();
    sync.dispose();
    disconnect.dispose();
    super.dispose();
  }
}

// A settings route owns these commands, while the provider owns the service.
// Leaving the route must not cancel a durable import or notify disposed UI.
mixin _DisposeAwareNotifier on ChangeNotifier {
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

class _PageCommand0<T> extends Command0<T> with _DisposeAwareNotifier {
  _PageCommand0(super.action);

  @override
  Future<void> execute() => _disposed ? Future.value() : super.execute();
}

class _PageCommand1<T, A> extends Command1<T, A> with _DisposeAwareNotifier {
  _PageCommand1(super.action);

  @override
  Future<void> execute(A argument) =>
      _disposed ? Future.value() : super.execute(argument);
}
