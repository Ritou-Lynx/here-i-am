import 'dart:async';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'health_hub.dart';
import 'notification_service.dart';
import 'wear_message_protocol.dart';

/// 实时健康主动陪伴：监听 [HealthHub.realtimeStream] 的心率+睡眠状态，
/// 在关键睡眠阶段转换时触发主动提醒（睡前陪伴 / 夜间关心 / 早晨问候）。
///
/// 这是"主动陪伴层"接入实时健康数据的第一个闭环。规则简单、克制：
///   1. 检测到入睡（awake → fallingAsleep/light）→ 睡前陪伴通知。
///   2. 夜间长时间未检测到心跳/睡眠（手表离线）→ 静默，不打扰。
///   3. 检测到醒来（睡眠态 → awake）→ 早晨问候。
///
/// 触发后按 checkin 的惯例：先发系统通知（payload 指向主角色，点击直达
/// 聊天），再把问候写进 [PersonaChatService] 的真实聊天消息，让用户打开
/// Chat 能看到、角色也有自己说过这句话的记忆。
///
/// 用冷却窗口 + 数据库级去重（同一角色同一文案在冷却期内不重复）避免
/// 重复推送，进程重启后内存冷却失效也不至于在 Chat 里刷重复问候。
class RealtimeHealthCompanion {
  RealtimeHealthCompanion._();
  static final RealtimeHealthCompanion instance = RealtimeHealthCompanion._();

  static final _logger = Logger('RealtimeHealthCompanion');

  StreamSubscription<RealtimeTelemetry>? _sub;
  bool _running = false;

  SleepStateLabel _lastSleep = SleepStateLabel.unknown;
  DateTime? _lastBedtimeNotified;
  DateTime? _lastWakeNotified;

  /// 通知冷却窗口：同一类型通知间隔至少 4 小时。
  static const Duration _cooldown = Duration(hours: 4);

  bool get isRunning => _running;

  void start() {
    if (_running) return;
    _running = true;
    _sub = HealthHub.instance.realtimeStream.listen(_onTelemetry);
    _logger.info('RealtimeHealthCompanion started');
  }

  void stop() {
    _running = false;
    _sub?.cancel();
    _sub = null;
  }

  void _onTelemetry(RealtimeTelemetry t) {
    final sleep = t.sleepState;
    if (sleep == _lastSleep) return; // 状态未变
    final prev = _lastSleep;
    _lastSleep = sleep;

    switch (sleep) {
      case SleepStateLabel.fallingAsleep:
      case SleepStateLabel.light:
        // 只有从清醒转入入睡才视为"睡前"（避免刚启动/睡中翻身误报）。
        if (prev == SleepStateLabel.awake) {
          _maybeNotifyBedtime();
        }
        break;
      case SleepStateLabel.awake:
        // 只有先前处于睡眠状态才视为"醒来"（避免刚启动就误报）。
        if (_isSleeping(prev)) {
          _maybeNotifyWake();
        }
        break;
      case SleepStateLabel.deep:
      case SleepStateLabel.rem:
      case SleepStateLabel.unknown:
        break;
    }
  }

  static bool _isSleeping(SleepStateLabel s) =>
      s == SleepStateLabel.fallingAsleep ||
      s == SleepStateLabel.light ||
      s == SleepStateLabel.deep ||
      s == SleepStateLabel.rem;

  Future<void> _maybeNotifyBedtime() async {
    if (_lastBedtimeNotified != null &&
        DateTime.now().difference(_lastBedtimeNotified!) < _cooldown) {
      return;
    }
    _lastBedtimeNotified = DateTime.now();
    await _sendAsCharacter(
      title: '看到你准备休息了',
      body: '心率平稳下来了，早点睡。睡前在想什么呢？',
    );
  }

  Future<void> _maybeNotifyWake() async {
    if (_lastWakeNotified != null &&
        DateTime.now().difference(_lastWakeNotified!) < _cooldown) {
      return;
    }
    _lastWakeNotified = DateTime.now();
    await _sendAsCharacter(
      title: '早上好',
      body: '睡醒啦。昨晚休息得怎么样？',
    );
  }

  /// 按 checkin 惯例触达：解析主角色 → 系统通知（payload=角色）→
  /// 写入真实聊天消息。数据库级去重兜底进程重启后的重复推送。
  Future<void> _sendAsCharacter({
    required String title,
    required String body,
  }) async {
    final characterId = await _resolvePrimaryCharacterId();

    if (characterId != null &&
        await _alreadySentWithinCooldown(characterId, body)) {
      _logger.info('companion notification deduped (already in chat): $body');
      return;
    }

    await NotificationService.instance.showAgentNotification(
      title: title,
      body: body,
      payload: characterId,
    );

    if (characterId != null) {
      try {
        await PersonaChatService.instance.addCharacterMessage(
          characterId,
          body,
          timestamp: DateTime.now(),
          isRead: false,
        );
        _logger.info('companion message persisted to chat: $body');
      } catch (e) {
        _logger.warning('Failed to persist companion chat message: $e');
      }
    }
  }

  Future<String?> _resolvePrimaryCharacterId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('current_user_id');
      if (userId == null) {
        _logger.warning('resolveCharacter: no current_user_id');
        return null;
      }
      if (!AppDatabase.isInitialized) {
        await AppDatabase.init(userId);
      }
      final character =
          await CharacterService.instance.getPrimaryCompanion(userId);
      if (character == null) {
        _logger.warning('resolveCharacter: no primary companion');
        return null;
      }
      return character.id;
    } catch (e) {
      _logger.warning('resolveCharacter failed: $e');
      return null;
    }
  }

  Future<bool> _alreadySentWithinCooldown(
      String characterId, String body) async {
    if (!AppDatabase.isInitialized) return false;
    try {
      final cutoff = DateTime.now().subtract(_cooldown);
      final dupe = await (AppDatabase.instance
              .select(AppDatabase.instance.personaChatMessages)
            ..where((t) =>
                t.characterId.equals(characterId) &
                t.isFromCharacter.equals(true) &
                t.content.equals(body) &
                t.timestamp.isBiggerThanValue(cutoff))
            ..limit(1))
          .getSingleOrNull();
      return dupe != null;
    } catch (e) {
      _logger.warning('companion dedup query failed: $e');
      return false;
    }
  }
}
