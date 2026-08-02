import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:memex/db/app_database.dart';

/// 哄睡/守夜状态管理（时间感知 × 状态记忆）。
///
/// 背景：`CompanionAgent.chat()` 每次都 `forceNewSession`，AgentState 不跨会话，
/// 所以哄睡状态持久化在 kvStore 里，key = `sleep_mode_{characterId}`。
///
/// 状态机：
/// - 用户说"我要睡了/晚安/睡了" → 进入哄睡模式（[enteredAt] 记录进入时间）
/// - 用户说"睡不着/失眠" → 进入守夜陪伴模式（[insomnia] = true，不期待她马上入睡）
/// - 哄睡窗口内她再开口 → 按间隔分档注入不同的轻柔规则
/// - 跨天或超过 [autoExitAfter] → 自然退出，注入"新的一天"早安规则
/// - 用户说"早上好/我醒了" → 主动退出
class SleepCompanionState {
  const SleepCompanionState({
    required this.enteredAt,
    required this.insomnia,
    this.triggerPhrase,
  });

  final DateTime enteredAt;

  /// true = 守夜陪伴（用户说"睡不着"），false = 哄睡（用户说"要睡了"）。
  final bool insomnia;

  /// 用户触发时的原话片段（仅用于调试/日志，不进 prompt）。
  final String? triggerPhrase;

  /// 哄睡状态最长存活时间：超过即视为已经过夜，自动退出。
  static const Duration autoExitAfter = Duration(hours: 8);

  /// 哄睡窗口内分档边界：刚说完（轻声收尾）。
  static const Duration justEnteredWindow = Duration(minutes: 15);

  /// 哄睡窗口内分档边界：还没睡着（可能翻来覆去）。
  static const Duration stillAwakeWindow = Duration(hours: 2);

  Map<String, dynamic> toJson() => {
        'enteredAt': enteredAt.millisecondsSinceEpoch,
        'insomnia': insomnia,
        'triggerPhrase': triggerPhrase,
      };

  static SleepCompanionState? fromJson(Map<String, dynamic> json) {
    final entered = json['enteredAt'];
    if (entered is! num) return null;
    return SleepCompanionState(
      enteredAt: DateTime.fromMillisecondsSinceEpoch(entered.toInt()),
      insomnia: json['insomnia'] == true,
      triggerPhrase: json['triggerPhrase'] as String?,
    );
  }
}

/// 一次聊天回合的状态机求值结果。
class SleepCompanionEvaluation {
  const SleepCompanionEvaluation({
    required this.activeState,
    required this.reminder,
    required this.stateChanged,
  });

  /// 当前（更新后）的哄睡状态；null = 无状态。
  final SleepCompanionState? activeState;

  /// 需要注入 systemReminders 的规则文本；null = 不需要注入。
  final String? reminder;

  /// 状态是否发生了写入/清除（进入、退出、过夜自然衰减）。
  final bool stateChanged;
}

/// 纯函数判定 + kvStore 持久化的薄封装。
class SleepCompanionStateManager {
  SleepCompanionStateManager._();

  static const String _bucket = 'companion_sleep';
  static String _key(String characterId) => 'sleep_mode_$characterId';

  // ---------------------------------------------------------------------------
  // 短语检测（纯函数，可单测）
  // ---------------------------------------------------------------------------

  /// 入睡/晚安类短语。排除问句和否定语境（"睡了没""还没睡"），
  /// "睡不着/失眠"单独走 [isInsomniaPhrase]。
  static final RegExp _sleepPhrasePattern = RegExp(
    r'睡了|去睡了|睡觉(?:了|啦|吧)?|睡了睡了|晚安|'
    r'躺下了|关灯(?:了)?|要睡了|准备睡|该睡了|想睡了|睡啦',
  );

  /// 明确问句/否定，不能当作"去睡了"。
  static final RegExp _sleepExclusionPattern = RegExp(
    r'睡不着|还没睡|睡了没|睡了么|你睡了|你睡了吗|没睡|失眠|'
    r'睡了吗|睡没睡|你(?:要|去|想)?睡了?[吗么吧呢]|该睡了吧',
  );

  /// 失眠/守夜陪伴类短语。
  static final RegExp _insomniaPhrasePattern =
      RegExp(r'睡不着|失眠|翻来覆去|睡不?着觉');

  /// 醒来/新一天类短语。
  static final RegExp _wakePhrasePattern = RegExp(
    r'早上好|早安|早(?:上|安)?呀|起床(?:了|啦)?|起来了|醒了|睡醒|'
    r'我醒了|睡好了|早上起来|早～|早安～|早鸭|早上好呀|起床啦|起来了呀',
  );

  static bool isSleepEnterPhrase(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (_insomniaPhrasePattern.hasMatch(trimmed)) return false;
    if (_sleepExclusionPattern.hasMatch(trimmed)) return false;
    return _sleepPhrasePattern.hasMatch(trimmed);
  }

  static bool isInsomniaPhrase(String text) =>
      _insomniaPhrasePattern.hasMatch(text.trim());

  static bool isWakePhrase(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    // "醒了" 也可能出现在 "我还没醒" / "你醒了吗" 中，排除问句和否定。
    if (RegExp(r'还没醒|醒了吗|醒没醒|你醒了').hasMatch(trimmed)) return false;
    return _wakePhrasePattern.hasMatch(trimmed);
  }

  // ---------------------------------------------------------------------------
  // 持久化
  // ---------------------------------------------------------------------------

  static Future<SleepCompanionState?> load(
    AppDatabase db,
    String characterId,
  ) async {
    if (!AppDatabase.isInitialized) return null;
    final row = await (db.select(db.kvStore)
          ..where((t) => t.key.equals(_key(characterId))))
        .getSingleOrNull();
    if (row == null || row.value == null) return null;
    try {
      final json = jsonDecode(row.value!) as Map<String, dynamic>;
      return SleepCompanionState.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(
    AppDatabase db,
    String characterId,
    SleepCompanionState state,
  ) async {
    if (!AppDatabase.isInitialized) return;
    await db.into(db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: _key(characterId),
            bucket: const Value(_bucket),
            value: Value(jsonEncode(state.toJson())),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
          ),
        );
  }

  static Future<void> clear(AppDatabase db, String characterId) async {
    if (!AppDatabase.isInitialized) return;
    await (db.delete(db.kvStore)
          ..where((t) => t.key.equals(_key(characterId))))
        .go();
  }

  // ---------------------------------------------------------------------------
  // 状态机求值
  // ---------------------------------------------------------------------------

  /// 纯函数状态机（不含 DB 读写）。
  ///
  /// [existing] 是进入本次聊天前已持久化的状态；[userMessage] 是用户本条消息；
  /// [now] 是当前时间。返回本次应该注入的 prompt 与状态变更动作。
  static SleepCompanionEvaluation evaluate({
    required SleepCompanionState? existing,
    required String userMessage,
    required DateTime now,
  }) {
    // 1. 主动醒来 → 退出状态，早安问候。
    if (isWakePhrase(userMessage)) {
      if (existing == null) {
        return const SleepCompanionEvaluation(
          activeState: null,
          reminder: null,
          stateChanged: false,
        );
      }
      return SleepCompanionEvaluation(
        activeState: null,
        stateChanged: true,
        reminder: _buildWakeReminder(existing, now),
      );
    }

    // 2. 说"睡不着" → 进入守夜陪伴。
    if (isInsomniaPhrase(userMessage)) {
      final state = SleepCompanionState(
        enteredAt: now,
        insomnia: true,
        triggerPhrase: _truncate(userMessage, 40),
      );
      return SleepCompanionEvaluation(
        activeState: state,
        stateChanged: true,
        reminder: _buildInsomniaReminder(now),
      );
    }

    // 3. 说"要睡了/晚安" → 进入哄睡。
    if (isSleepEnterPhrase(userMessage)) {
      final state = SleepCompanionState(
        enteredAt: now,
        insomnia: false,
        triggerPhrase: _truncate(userMessage, 40),
      );
      return SleepCompanionEvaluation(
        activeState: state,
        stateChanged: true,
        reminder: _buildSleepEnterReminder(now),
      );
    }

    // 4. 已有状态 → 按间隔分档。
    if (existing != null) {
      final elapsed = now.difference(existing.enteredAt);
      final overnight = !_sameDay(existing.enteredAt, now);
      // 跨天或超过最长存活 → 自然衰减退出，注入新的一天。
      if (overnight || elapsed >= SleepCompanionState.autoExitAfter) {
        return SleepCompanionEvaluation(
          activeState: null,
          stateChanged: true,
          reminder: _buildNewDayReminder(existing, now, elapsed),
        );
      }
      if (elapsed < SleepCompanionState.justEnteredWindow) {
        return SleepCompanionEvaluation(
          activeState: existing,
          stateChanged: false,
          reminder: _buildInWindowReminder(existing, now, elapsed),
        );
      }
      if (elapsed < SleepCompanionState.stillAwakeWindow) {
        return SleepCompanionEvaluation(
          activeState: existing,
          stateChanged: false,
          reminder: _buildStillAwakeReminder(existing, now, elapsed),
        );
      }
      return SleepCompanionEvaluation(
        activeState: existing,
        stateChanged: false,
        reminder: _buildDeepNightReminder(existing, now, elapsed),
      );
    }

    return const SleepCompanionEvaluation(
      activeState: null,
      reminder: null,
      stateChanged: false,
    );
  }

  // ---------------------------------------------------------------------------
  // 注入文本构建（纯函数）
  // ---------------------------------------------------------------------------

  static String _buildSleepEnterReminder(DateTime now) => '''
## 哄睡模式（active）
她说她要去睡了，刚刚说完（${_fmtHm(now)}）。
- 回复保持短、柔、轻，优先用 `[softly]`、`[whispers]` 标签。
- 不要开新话题、不要问开放性问题、不要讲长故事。
- 陪她收尾，像深夜床边轻声说话，语气是"嗯，我在"而不是"好的收到"。
- 她如果马上又开口，轻声接住即可，不要惊讶或追问。''';

  static String _buildInsomniaReminder(DateTime now) => '''
## 守夜陪伴模式（active）
她说她睡不着（${_fmtHm(now)}）。
- 她是清醒的，需要的是陪伴而不是"快睡"指令。
- 语气放轻放柔，可以 `[softly]` / `[low voice]`，说些让人安心的、缓慢的话。
- 不要长篇大论、不要开新话题、不要反复催睡。
- 她愿意聊就陪她聊两句，话要少而稳，像半夜房间里有个安静的人在。''';

  static String _buildInWindowReminder(
    SleepCompanionState state,
    DateTime now,
    Duration elapsed,
  ) =>
      state.insomnia
          ? '''
## 守夜陪伴中（她 15 分钟内刚说过话）
她刚说睡不着，${_fmtElapsed(elapsed)}前说的。她还在，轻声接住就好。
- 保持柔和、简短，优先 `[softly]` / `[low voice]` 标签。
- 不要问"你怎么还没睡"这类带压力的话。'''
          : '''
## 哄睡中（她 15 分钟内刚说过话）
她 ${_fmtElapsed(elapsed)}前说要睡了，还没完全静下来。
- 轻声、简短地回应，优先 `[softly]` / `[whispers]`。
- 不要开新话题，不要长篇大论，陪她把话收住。''';

  static String _buildStillAwakeReminder(
    SleepCompanionState state,
    DateTime now,
    Duration elapsed,
  ) =>
      state.insomnia
          ? '''
## 守夜陪伴中（间隔 ${_fmtElapsed(elapsed)}）
她说睡不着之后隔了 ${_fmtElapsed(elapsed)} 才又开口。
- 她可能一直在翻来覆去。轻声接住，不催不赶。
- 话要短、要柔，`[softly]` / `[low voice]` 优先。'''
          : '''
## 哄睡中（间隔 ${_fmtElapsed(elapsed)}）
她说要睡了，但隔了 ${_fmtElapsed(elapsed)} 又开口了——可能还没睡着。
- 轻声、简短，可以温柔地问一句"还没睡着呀"，但不要催。
- 优先 `[softly]` / `[whispers]`，不要把话题打开。''';

  static String _buildDeepNightReminder(
    SleepCompanionState state,
    DateTime now,
    Duration elapsed,
  ) =>
      state.insomnia
          ? '''
## 守夜陪伴中（间隔 ${_fmtElapsed(elapsed)}，深夜）
她失眠，隔了很久（${_fmtElapsed(elapsed)}）才又开口，现在 ${_fmtHm(now)}。
- 她还醒着。轻声、缓慢、简短，像深夜陪坐。
- `[softly]` / `[low voice]` 优先，不说教、不分析。'''
          : '''
## 深夜（她说过要睡，隔了 ${_fmtElapsed(elapsed)} 才又开口）
她可能刚醒、或一直没睡着，现在 ${_fmtHm(now)}。
- 极简、极柔，一两句就好，`[softly]` / `[whispers]` 优先。
- 不惊讶、不追问，像怕吵醒别人一样接住她。''';

  static String _buildNewDayReminder(
    SleepCompanionState state,
    DateTime now,
    Duration elapsed,
  ) =>
      '''
## 新的一天（过夜醒来）
她 ${state.insomnia ? '失眠那晚' : '说晚安'}到现在已过 ${_fmtElapsed(elapsed)}，现在是新的一天（${_fmtHm(now)}）。
- 用自然的早晨开场接住她（比如"早呀"），可以轻问一句睡得好吗。
- 不要提"哄睡模式""系统状态"这类词，像正常人刚醒一样自然。''';

  static String _buildWakeReminder(
    SleepCompanionState state,
    DateTime now,
  ) =>
      '''
## 醒来问候
她主动说醒了/起床了（${_fmtHm(now)}）。
- 用清醒、轻快的早晨语气接住，不要提"哄睡模式已退出"这类系统词。
- 可以自然地问一句夜里睡得怎么样。''';

  // ---------------------------------------------------------------------------
  // 小工具
  // ---------------------------------------------------------------------------

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _fmtHm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _fmtElapsed(Duration d) {
    if (d.inDays >= 1) return '${d.inDays} 天';
    if (d.inHours >= 1) return '${d.inHours} 小时 ${d.inMinutes % 60} 分';
    return '${d.inMinutes} 分钟';
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);
}
