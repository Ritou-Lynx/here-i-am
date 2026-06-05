import 'dart:async';

import 'package:flutter/services.dart';

/// Bridges Android MediaSession button events into the voice input controller.
class MediaButtonService {
  MediaButtonService._() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static final MediaButtonService instance = MediaButtonService._();
  static final Object _defaultOwner = Object();

  static const MethodChannel _channel =
      MethodChannel('com.memexlab.memex/media_buttons');

  final Map<Object, _MediaButtonCallbacks> _callbacksByOwner = {};
  final Set<Object> _activeOwners = {};
  final List<Object> _ownerStack = [];
  Object? _currentOwner;

  void setOnToggle(VoidCallback cb, {Object? owner}) {
    final actualOwner = owner ?? _defaultOwner;
    _callbacksFor(actualOwner).onToggle = cb;
    _promoteOwner(actualOwner);
  }

  void setOnCancel(VoidCallback cb, {Object? owner}) {
    final actualOwner = owner ?? _defaultOwner;
    _callbacksFor(actualOwner).onCancel = cb;
    _promoteOwner(actualOwner);
  }

  void clearCallbacks({Object? owner}) {
    final actualOwner = owner ?? _defaultOwner;
    _callbacksByOwner.remove(actualOwner);
    _activeOwners.remove(actualOwner);
    _ownerStack.remove(actualOwner);
    _currentOwner = _resolveCurrentOwner();
  }

  Future<void> activate({Object? owner}) async {
    final actualOwner = owner ?? _defaultOwner;
    _activeOwners.add(actualOwner);
    _promoteOwner(actualOwner);
    await _channel.invokeMethod<void>('activate');
  }

  Future<void> deactivate({Object? owner}) async {
    final actualOwner = owner ?? _defaultOwner;
    _activeOwners.remove(actualOwner);
    _ownerStack.remove(actualOwner);
    _currentOwner = _resolveCurrentOwner();
    if (_currentOwner == null) {
      await _channel.invokeMethod<void>('deactivate');
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    final callbacks = _currentCallbacks;
    switch (call.method) {
      case 'voiceToggle':
        callbacks?.onToggle?.call();
        break;
      case 'voiceCancel':
        callbacks?.onCancel?.call();
        break;
      default:
        throw PlatformException(
          code: 'unimplemented',
          message: 'Unknown media button method: ${call.method}',
        );
    }
  }

  _MediaButtonCallbacks _callbacksFor(Object owner) {
    return _callbacksByOwner.putIfAbsent(owner, _MediaButtonCallbacks.new);
  }

  _MediaButtonCallbacks? get _currentCallbacks {
    final owner = _currentOwner;
    if (owner == null) return null;
    return _callbacksByOwner[owner];
  }

  void _promoteOwner(Object owner) {
    _ownerStack.remove(owner);
    _ownerStack.add(owner);
    _currentOwner = _resolveCurrentOwner();
  }

  Object? _resolveCurrentOwner() {
    for (final owner in _ownerStack.reversed) {
      if (_activeOwners.contains(owner) &&
          _callbacksByOwner[owner]?.hasAnyCallback == true) {
        return owner;
      }
    }
    return null;
  }
}

class _MediaButtonCallbacks {
  VoidCallback? onToggle;
  VoidCallback? onCancel;

  bool get hasAnyCallback => onToggle != null || onCancel != null;
}
