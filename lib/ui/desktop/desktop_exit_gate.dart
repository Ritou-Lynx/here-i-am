library;

import 'package:flutter/services.dart';

/// Small, injectable close gate for the normal Windows desktop window.
///
/// Closing is deliberately fail-closed: a false/throwing owner leaves the
/// window open so the same owners can be retried. It has no candidate-host,
/// fixed-task, database, or witness responsibilities.
class DesktopExitGate {
  DesktopExitGate({
    required void Function() fenceConversation,
    required Future<bool> Function() closeConversation,
    required Future<bool> Function() closeQueue,
  })  : _fenceConversation = fenceConversation,
        _closeConversation = closeConversation,
        _closeQueue = closeQueue;

  final void Function() _fenceConversation;
  final Future<bool> Function() _closeConversation;
  final Future<bool> Function() _closeQueue;
  Future<bool>? _attempt;
  bool _fenced = false;

  Future<bool> close() {
    final active = _attempt;
    if (active != null) return active;
    if (!_fenced) {
      _fenceConversation();
      _fenced = true;
    }
    late final Future<bool> attempt;
    attempt = _close().whenComplete(() {
      if (identical(_attempt, attempt)) _attempt = null;
    });
    return _attempt = attempt;
  }

  Future<bool> _close() async {
    try {
      if (!await _closeConversation()) return false;
      return await _closeQueue();
    } on Object {
      return false;
    }
  }
}

/// Bridges a Windows WM_CLOSE request into [DesktopExitGate]. The native runner
/// keeps the window alive until this side explicitly allows destruction.
class DesktopWindowExitChannel {
  DesktopWindowExitChannel._();

  static const MethodChannel _channel =
      MethodChannel('com.memexlab.memex/desktop_exit');

  static void install(Future<bool> Function() close) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'request_exit') {
        throw MissingPluginException('Unsupported desktop exit method');
      }
      final arguments = call.arguments;
      if (arguments is! Map || arguments['request_id'] is! int) {
        throw PlatformException(
            code: 'invalid_exit_request', message: 'Missing request_id');
      }
      final requestId = arguments['request_id'] as int;
      var closed = false;
      try {
        closed = await close();
      } on Object {
        closed = false;
      }
      await _channel.invokeMethod<void>(
        closed ? 'allow_close' : 'close_cancelled',
        {'request_id': requestId},
      );
    });
  }
}
