import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:memex/utils/result.dart';
import 'personal_data_hub_runtime.dart';

/// One owner per Flutter engine. Database replacement must await [suspend]
/// before closing the old connection, then call [reload] after opening its heir.
class PersonalDataHubRuntimeOwner extends ChangeNotifier {
  PersonalDataHubRuntimeOwner({
    required Future<PersonalDataHubRuntime> Function() create,
  }) : _create = create {
    current = this;
    _begin();
  }

  static PersonalDataHubRuntimeOwner? current;
  final Future<PersonalDataHubRuntime> Function() _create;
  late Future<Result<PersonalDataHubRuntime>> _future;
  Future<Result<PersonalDataHubRuntime>>? _creation;
  PersonalDataHubRuntime? _runtime;
  Future<void>? _stopping, _reloading;
  int _epoch = 0, _request = 0;
  bool _disposed = false, _suspended = false;

  Future<Result<PersonalDataHubRuntime>> get future => _future;

  void _begin() {
    _suspended = false;
    final epoch = ++_epoch;
    _future = _creation = _createAndAdopt(epoch);
  }

  Future<Result<PersonalDataHubRuntime>> _createAndAdopt(int epoch) async {
    final result = await runResult(_create);
    if (_disposed || _suspended || epoch != _epoch) {
      if (result case Ok<PersonalDataHubRuntime>(:final value)) {
        final released = await runResultVoid(value.dispose);
        if (released case Error<void>(:final error, :final stackTrace)) {
          return Error(error, stackTrace);
        }
      }
      return Error(StateError('Runtime creation was superseded'));
    }
    if (result case Ok<PersonalDataHubRuntime>(:final value)) {
      _runtime = value;
    }
    return result;
  }

  /// Invalidates UI publication immediately; waits for even a pending factory
  /// and its teardown before the caller may close the database.
  Future<void> suspend() {
    ++_request;
    _reloading = null;
    return _stop();
  }

  Future<void> _stop() {
    if (_stopping case final active?) return active;
    if (_suspended) return Future.value();
    _suspended = true;
    ++_epoch;
    final runtime = _runtime, creation = _creation;
    _runtime = null;
    _future = Future.value(Error(StateError('Runtime is suspended')));
    final done = Completer<void>();
    _stopping = done.future;
    if (!_disposed) notifyListeners();
    unawaited(() async {
      final released = await runResultVoid(() async {
        final disposal = await runResultVoid(() async {
          await runtime?.dispose();
        });
        // A stale factory disposes its own result before completing.
        await creation;
        disposal.valueOrThrow;
      });
      _stopping = null;
      switch (released) {
        case Ok<void>():
          done.complete();
        case Error<void>(:final error, :final stackTrace):
          done.completeError(error, stackTrace);
      }
    }());
    return done.future;
  }

  /// Concurrent reset requests share one replacement. A later suspend wins
  /// over a reload that is still waiting for the previous runtime to close.
  Future<void> reload() {
    if (_disposed) return Future.value();
    if (_reloading case final active?) return active;
    final request = ++_request;
    final done = Completer<void>();
    _reloading = done.future;
    unawaited(() async {
      final result = await runResultVoid(() async {
        await _stop();
        if (_disposed || request != _request) return;
        _begin();
        notifyListeners();
        await _creation;
      });
      if (identical(_reloading, done.future)) _reloading = null;
      switch (result) {
        case Ok<void>():
          done.complete();
        case Error<void>(:final error, :final stackTrace):
          done.completeError(error, stackTrace);
      }
    }());
    return done.future;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_request;
    if (identical(current, this)) current = null;
    // ChangeNotifier disposal is synchronous; observe eventual async cleanup.
    unawaited(runResultVoid(_stop));
    super.dispose();
  }
}
