/// Human-operated Chinese IME acceptance for the production card editor.
///
/// This is a normal interactive Windows application, not a `flutter test`
/// runner. It mounts the production desktop route and editor against a
/// temporary Drift database and rich-text directory, then reopens that same
/// database after acceptance to verify persistence without touching user data.
///
/// Run:
///   flutter run -d windows -t integration_test/whiteboard_manual_chinese_ime_windows.dart
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/routing/desktop_route_wrapper.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/card_rich_text_editor_screen.dart';

const _cardId = 'manual_chinese_ime_acceptance';
const _requiredChinese = '中文输入法验收';
const _requiredContent = '今天继续整理白板';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final coordinator = await _ManualAcceptanceCoordinator.create();
  runApp(_ManualImeApp(coordinator: coordinator));
}

class _ManualAcceptanceCoordinator {
  _ManualAcceptanceCoordinator._({
    required this.root,
    required this.dbFile,
    required this.db,
    required this.repository,
  });

  final Directory root;
  final File dbFile;
  AppDatabase db;
  UnifiedCardRepository repository;
  final result = ValueNotifier<_VerificationResult>(
    const _VerificationResult(_VerificationStatus.waiting, ''),
  );

  bool _finished = false;
  bool _dbOpen = true;

  static Future<_ManualAcceptanceCoordinator> create() async {
    final root =
        await Directory.systemTemp.createTemp('ui0_manual_chinese_ime_');
    final dbFile =
        File('${root.path}${Platform.pathSeparator}whiteboard.sqlite');
    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    await repository.createTextCard(
      cardId: _cardId,
      title: '中文输入法手工验收（临时卡片）',
    );
    CardRichTextEditorScreen.setRepositoryForTesting(repository);
    return _ManualAcceptanceCoordinator._(
      root: root,
      dbFile: dbFile,
      db: db,
      repository: repository,
    );
  }

  Future<void> verify(GoRouter router) async {
    if (_finished) return;
    _finished = true;
    result.value = const _VerificationResult(
      _VerificationStatus.verifying,
      '正在关闭并重新打开临时数据库…',
    );
    router.go('/result');
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 120));

    try {
      CardRichTextEditorScreen.setRepositoryForTesting(null);
      await db.close();
      _dbOpen = false;
      db = AppDatabase.forTesting(NativeDatabase(dbFile));
      _dbOpen = true;
      repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
      CardRichTextEditorScreen.setRepositoryForTesting(repository);
      final restarted = await repository.getCard(_cardId);
      final body = restarted?.card.body ?? '';
      final passed = restarted != null &&
          body.contains(_requiredChinese) &&
          body.contains(_requiredContent) &&
          restarted.documentState == CardDocumentState.available;
      if (!passed) {
        result.value = const _VerificationResult(
          _VerificationStatus.failed,
          '数据库已经重开，但保存内容中缺少指定中文文本，或富文本文档不可用。',
        );
        debugPrint('MANUAL_CHINESE_IME_ACCEPTANCE=FAIL persistence');
        return;
      }
      result.value = const _VerificationResult(
        _VerificationStatus.passed,
        '中文文本与富文本文档在数据库重开后均已恢复。',
      );
      debugPrint('MANUAL_CHINESE_IME_ACCEPTANCE=PASS');
    } catch (error, stackTrace) {
      result.value = _VerificationResult(
        _VerificationStatus.failed,
        '重新打开临时数据库时失败：$error',
      );
      debugPrint('MANUAL_CHINESE_IME_ACCEPTANCE=FAIL $error\n$stackTrace');
    }
  }

  void reportFailure(GoRouter router) {
    if (_finished) return;
    _finished = true;
    result.value = const _VerificationResult(
      _VerificationStatus.failed,
      '已记录真人验收失败；请关闭窗口并把具体现象告诉主任务。',
    );
    debugPrint('MANUAL_CHINESE_IME_ACCEPTANCE=FAIL human_report');
    router.go('/result');
  }

  Future<void> close() async {
    CardRichTextEditorScreen.setRepositoryForTesting(null);
    if (_dbOpen) {
      await db.close();
      _dbOpen = false;
    }
    if (root.existsSync()) root.deleteSync(recursive: true);
    exit(result.value.status == _VerificationStatus.passed ? 0 : 1);
  }
}

class _ManualImeApp extends StatefulWidget {
  const _ManualImeApp({required this.coordinator});

  final _ManualAcceptanceCoordinator coordinator;

  @override
  State<_ManualImeApp> createState() => _ManualImeAppState();
}

class _ManualImeAppState extends State<_ManualImeApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/cards/$_cardId',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const _ManualExitDestination(),
        ),
        GoRoute(
          path: '/cards',
          builder: (_, __) => const _ManualExitDestination(),
        ),
        GoRoute(
          path: '/cards/:cardId',
          builder: (_, state) => DesktopRouteWrapper(
            title: '卡片编辑',
            childOwnsPageTitle: true,
            desktopOnly: true,
            desktopPlatformOverride: true,
            childBuilder: (_) => Stack(
              children: [
                Positioned.fill(
                  child: CardRichTextEditorScreen(
                    cardId: state.pathParameters['cardId']!,
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: _ManualAcceptancePanel(
                    onDecision: (accepted) {
                      if (accepted) {
                        unawaited(widget.coordinator.verify(_router));
                      } else {
                        widget.coordinator.reportFailure(_router);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/result',
          builder: (_, __) => _VerificationScreen(
            coordinator: widget.coordinator,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'UI-0 中文输入法手工验收（临时数据）',
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

class _ManualAcceptancePanel extends StatefulWidget {
  const _ManualAcceptancePanel({required this.onDecision});

  final ValueChanged<bool> onDecision;

  @override
  State<_ManualAcceptancePanel> createState() => _ManualAcceptancePanelState();
}

class _ManualAcceptancePanelState extends State<_ManualAcceptancePanel> {
  bool _expanded = true;
  bool _compositionPassed = false;
  bool _savePassed = false;
  bool _exitGuardPassed = false;

  bool get _allPassed => _compositionPassed && _savePassed && _exitGuardPassed;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Material(
      key: const ValueKey('manual_ime_acceptance_panel'),
      color: tokens.surfaceRaised,
      elevation: 12,
      shadowColor: tokens.dark.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: _expanded ? 348 : 230,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: tokens.divider),
          borderRadius: BorderRadius.circular(12),
        ),
        child: _expanded ? _buildExpanded(tokens) : _buildCollapsed(tokens),
      ),
    );
  }

  Widget _buildCollapsed(DesktopWorkspaceTokens tokens) {
    return Row(
      children: [
        Icon(Icons.keyboard_alt_outlined, color: tokens.action, size: 19),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '中文 IME 验收',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          tooltip: '展开验收清单',
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _expanded = true),
          icon: const Icon(Icons.open_in_full_rounded, size: 17),
        ),
      ],
    );
  }

  Widget _buildExpanded(DesktopWorkspaceTokens tokens) {
    final instructionStyle = TextStyle(
      color: tokens.textMuted,
      fontSize: 12,
      height: 1.45,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.keyboard_alt_outlined, color: tokens.action, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '真人中文 IME 验收 · 临时数据',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: '收起后开始输入',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _expanded = false),
              icon: const Icon(Icons.close_fullscreen_rounded, size: 17),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('1. 收起本面板，切换真实中文输入法。', style: instructionStyle),
        Text('2. 在正文输入：', style: instructionStyle),
        SelectableText(
          '中文输入法验收：今天继续整理白板。\nEnglish 123',
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 12,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text('3. 用 Ctrl+S 保存并看到“已保存”。', style: instructionStyle),
        Text(
          '4. 再输入“未保存测试”，点页面返回，弹窗选“取消”；确认仍在编辑页后删掉这段并再次保存。',
          style: instructionStyle,
        ),
        const SizedBox(height: 8),
        _check(
          value: _compositionPassed,
          label: '候选、组合态、上屏与光标都正常',
          onChanged: (value) => setState(() => _compositionPassed = value),
        ),
        _check(
          value: _savePassed,
          label: 'Ctrl+S 保存后显示“已保存”',
          onChanged: (value) => setState(() => _savePassed = value),
        ),
        _check(
          value: _exitGuardPassed,
          label: '未保存退出→取消后内容仍保留',
          onChanged: (value) => setState(() => _exitGuardPassed = value),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => widget.onDecision(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: tokens.error,
                  side: BorderSide(color: tokens.error),
                ),
                child: const Text('发现问题'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _allPassed ? () => widget.onDecision(true) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.action,
                  foregroundColor: tokens.canvas,
                ),
                child: const Text('完成并校验'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _check({
    required bool value,
    required String label,
    required ValueChanged<bool> onChanged,
  }) {
    return CheckboxListTile(
      value: value,
      onChanged: (next) => onChanged(next ?? false),
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _VerificationScreen extends StatelessWidget {
  const _VerificationScreen({required this.coordinator});

  final _ManualAcceptanceCoordinator coordinator;

  @override
  Widget build(BuildContext context) {
    return DesktopWorkspaceTheme(
      child: ValueListenableBuilder<_VerificationResult>(
        valueListenable: coordinator.result,
        builder: (context, result, _) {
          final tokens = DesktopWorkspaceTokens.of(context);
          final verifying = result.status == _VerificationStatus.verifying;
          final passed = result.status == _VerificationStatus.passed;
          return Scaffold(
            backgroundColor: tokens.canvas,
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: tokens.surfaceRaised,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: tokens.divider),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (verifying)
                        const CircularProgressIndicator()
                      else
                        Icon(
                          passed
                              ? Icons.check_circle_outline_rounded
                              : Icons.error_outline_rounded,
                          size: 42,
                          color: passed ? tokens.action : tokens.error,
                        ),
                      const SizedBox(height: 18),
                      Text(
                        verifying
                            ? '正在复验保存结果'
                            : passed
                                ? '真人中文 IME 验收通过'
                                : '真人中文 IME 验收未通过',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        result.message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      if (!verifying) ...[
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () => unawaited(coordinator.close()),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                passed ? tokens.action : tokens.error,
                            foregroundColor: tokens.canvas,
                          ),
                          child: const Text('关闭验收窗口'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ManualExitDestination extends StatelessWidget {
  const _ManualExitDestination();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('已离开编辑器；请关闭窗口并重新开始本次验收。'),
      ),
    );
  }
}

enum _VerificationStatus { waiting, verifying, passed, failed }

class _VerificationResult {
  const _VerificationResult(this.status, this.message);

  final _VerificationStatus status;
  final String message;
}
