import 'dart:async';
import 'dart:io';

import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:uuid/uuid.dart';

import 'package:memex/agent/built_in_tools/initiate_call_tool.dart';
import 'package:memex/ui/core/widgets/local_image.dart';
import 'package:memex/utils/logger.dart';

/// Wraps `flutter_callkit_incoming` to show a real system-level incoming-call
/// screen (full-screen, persistent ringing, accept/decline) for companion calls.
///
/// Self-contained — no MemexRouter dependency. The app layer wires [onAccept] /
/// [onDecline] (e.g. in main.dart) to navigate or record a missed-call memory.
class CallkitService {
  CallkitService._();
  static final CallkitService instance = CallkitService._();

  static final _log = getLogger('CallkitService');
  static const _uuid = Uuid();

  /// Fired when the user accepts a companion call. Argument is characterId.
  void Function(String characterId)? onAccept;

  /// Fired when the user declines/misses a companion call. Argument is characterId.
  void Function(String characterId)? onDecline;

  StreamSubscription<CallEvent?>? _sub;
  // callId → characterId (in-memory; lost if the process is killed).
  final Map<String, String> _callToCharacter = {};

  /// Start listening for CallKit events. Call once at app startup.
  void init() {
    _sub ??= FlutterCallkitIncoming.onEvent.listen(_handleEvent);
    _log.info('CallkitService initialized');
  }

  Future<void> _handleEvent(CallEvent? event) async {
    if (event == null) return;
    switch (event) {
      case CallEventActionCallAccept(:final id):
        final cid = await _resolveCharacter(id);
        _log.info('CallKit accept: callId=$id characterId=$cid');
        if (cid != null) onAccept?.call(cid);
        break;
      case CallEventActionCallDecline(:final id):
        final cid = await _resolveCharacter(id);
        _log.info('CallKit decline: callId=$id characterId=$cid');
        if (cid != null) onDecline?.call(cid);
        await _cleanup(id);
        break;
      case CallEventActionCallTimeout(:final id):
        final cid = await _resolveCharacter(id);
        _log.info('CallKit timeout (missed): callId=$id characterId=$cid');
        if (cid != null) onDecline?.call(cid);
        await _cleanup(id);
        break;
      case CallEventActionCallEnded(:final id):
        await _cleanup(id);
        break;
      default:
        break;
    }
  }

  /// Resolve characterId for a callId. Falls back to the KVStore pending-call
  /// record (covers the case where the process was killed and restarted).
  Future<String?> _resolveCharacter(String callId) async {
    final inMemory = _callToCharacter[callId];
    if (inMemory != null) return inMemory;
    final pending = await readPendingCall();
    return pending?.characterId;
  }

  Future<void> _cleanup(String callId) async {
    _callToCharacter.remove(callId);
  }

  /// Show a system incoming-call screen for [characterId].
  /// Returns the generated callId.
  Future<String> showIncomingCall({
    required String characterId,
    required String nameCaller,
    String? avatarUrl,
  }) async {
    final id = _uuid.v4();
    _callToCharacter[id] = characterId;

    final resolvedAvatar = _resolveAvatar(avatarUrl);

    final params = CallKitParams(
      id: id,
      nameCaller: nameCaller,
      appName: 'Memex',
      avatar: resolvedAvatar,
      handle: '语音通话',
      type: 0, // audio
      duration: 45000, // ring for 45s then timeout
      extra: {'characterId': characterId},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0A0C10',
        actionColor: '#4CAF50',
        textColor: '#FFFFFF',
        incomingCallNotificationChannelName: 'Companion Call',
        isShowFullLockedScreen: true,
        isImportant: true,
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
    _log.info('showCallkitIncoming: $nameCaller (callId=$id, avatar=$resolvedAvatar)');
    return id;
  }

  /// Convert a CharacterModel.avatar value into something the (patched) CallKit
  /// incoming screen can display.
  ///
  /// Our vendored fork of flutter_callkit_incoming restores local file paths
  /// that were wrongly prefixed as flutter assets, so we can now feed it a
  /// `file://<abs path>` and Coil will render it. Resolution:
  /// - remote http(s) URL → passed through
  /// - tokenized local-server URL (127.0.0.1) → resolved to file://<abs path>
  /// - bare absolute path → file://<path>
  /// - DiceBear seed / unresolvable → null (built-in default avatar)
  String? _resolveAvatar(String? avatar) {
    if (avatar == null || avatar.trim().isEmpty) return null;

    if (avatar.startsWith('http://127.0.0.1')) {
      final path = LocalImage.resolveLocalFilePath(avatar);
      if (path != null && File(path).existsSync()) return 'file://$path';
      return null;
    }
    if (avatar.startsWith('http://') || avatar.startsWith('https://')) {
      return avatar;
    }
    if (avatar.startsWith('file://')) {
      final path = avatar.substring(7);
      return File(path).existsSync() ? avatar : null;
    }
    if (avatar.startsWith('/')) {
      return File(avatar).existsSync() ? 'file://$avatar' : null;
    }
    // DiceBear seed or anything we can't turn into an image file.
    return null;
  }

  Future<void> endAll() async {
    await FlutterCallkitIncoming.endAllCalls();
    _callToCharacter.clear();
  }

  /// Android 14+: whether the app may use full-screen intents (full-screen
  /// ringing). If false, [requestFullScreenIntentPermission] sends the user to
  /// the system setting.
  Future<bool> canUseFullScreenIntent() =>
      FlutterCallkitIncoming.canUseFullScreenIntent();

  Future<void> requestFullScreenIntentPermission() =>
      FlutterCallkitIncoming.requestFullIntentPermission();

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
