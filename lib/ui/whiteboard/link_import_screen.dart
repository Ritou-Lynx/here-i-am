/// Link import screen — W3 production body.
///
/// Route: `/import` (registered by the W6 integration base; router.dart /
/// routes.dart are NOT touched — this file only replaces the placeholder
/// body).
///
/// Flow: paste URL → safe fetch via [LinkIngestionService] (SSRF-protected,
/// DNS-pinned transport) → the `IngestionResult` is presented honestly in
/// one of four states (ok / failed / needsAuth / unsupported) → the user
/// **explicitly** taps "存入卡片库" to create the Card — the fetch itself
/// never writes a Card.
///
/// Restart recovery: recent imports are re-read from the Drift-backed
/// `UnifiedCardRepository` on every open; re-importing an already-known URL is
/// idempotent (no duplicate Card, no silent copy).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/data/whiteboard/ingestion/link_ingestion_service.dart';
import 'package:memex/data/whiteboard/ingestion/shared_link_input_parser.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_data_bootstrap.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/desktop/widgets/desktop_page_title.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

/// Entry point for ordinary link ingestion.
///
/// [service] / [storeDirResolver] are injectable for tests; production uses
/// the unified Drift repository plus its app-support object root.
class LinkImportScreen extends StatefulWidget {
  final LinkIngestionService? service;
  final Future<Directory> Function()? storeDirResolver;

  const LinkImportScreen({super.key, this.service, this.storeDirResolver});

  @override
  State<LinkImportScreen> createState() => _LinkImportScreenState();
}

class _RecentImport {
  final CardContract card;
  final String canonicalUrl;
  final String? provider;
  final int versionCount;
  final DateTime createdAt;

  const _RecentImport({
    required this.card,
    required this.canonicalUrl,
    this.provider,
    required this.versionCount,
    required this.createdAt,
  });
}

class _LinkImportScreenState extends State<LinkImportScreen> {
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode(debugLabel: 'link-import-url');
  final FocusNode _fetchFocusNode = FocusNode(debugLabel: 'link-import-fetch');
  final FocusNode _cancelPreviewFocusNode =
      FocusNode(debugLabel: 'link-import-cancel-preview');
  final FocusNode _commitFocusNode =
      FocusNode(debugLabel: 'link-import-commit');

  LinkIngestionService? _service;
  String? _storeError;
  bool _fetching = false;
  bool _cardBusy = false;
  String? _inputError;
  String? _recentError;
  String? _sourceLookupWarning;

  LinkIngestionOutcome? _outcome;
  CardContract? _existingCard;
  bool _matchesExistingVersion = false;
  bool _cardSaved = false;

  List<_RecentImport> _recent = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _urlFocusNode.dispose();
    _fetchFocusNode.dispose();
    _cancelPreviewFocusNode.dispose();
    _commitFocusNode.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final LinkIngestionService service;
    try {
      service = widget.service ?? await _createService();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _storeError = '存储连接暂时不可用。请重新打开桌面应用后再试。';
      });
      return;
    }
    if (!mounted) return;
    setState(() => _service = service);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _urlFocusNode.requestFocus();
    });
    await _loadRecent();
  }

  Future<LinkIngestionService> _createService() async {
    if (widget.storeDirResolver != null) {
      final root = await widget.storeDirResolver!();
      return LinkIngestionService(
        repository: UnifiedCardRepository(
          db: AppDatabase.instance,
          whiteboardRoot: root,
        ),
      );
    }
    final repository = await WhiteboardDataBootstrap.productionRepository();
    return LinkIngestionService(
      repository: repository,
    );
  }

  Future<void> _loadRecent() async {
    final service = _service;
    if (service == null) return;
    try {
      final cards = await service.listCards();
      final recent = <_RecentImport>[];
      for (final card in cards) {
        final record = card.sourceId != null
            ? await service.getSource(card.sourceId!)
            : null;
        recent.add(_RecentImport(
          card: card,
          canonicalUrl:
              record?.source.metadata['canonical_url'] as String? ?? '',
          provider: record?.source.provider,
          versionCount: record?.versions.length ?? 1,
          createdAt: card.createdAt,
        ));
      }
      recent.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _recent = recent;
        _recentError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recentError = '最近列表刷新失败。已保存的卡片与版本不受影响，可稍后重新进入本页刷新。';
      });
    }
  }

  // -----------------------------------------------------------------------
  // Actions
  // -----------------------------------------------------------------------

  Future<void> _fetch() async {
    final service = _service;
    if (service == null || _fetching || _cardBusy) return;
    if (_urlController.text.trim().isEmpty) {
      setState(() => _inputError = '请输入要导入的链接');
      return;
    }
    final parsedInput = parseSharedLinkInput(_urlController.text);
    if (parsedInput == null) {
      setState(() => _inputError = '没有找到可导入的 http(s) 链接');
      return;
    }
    final url = await _chooseUrl(parsedInput);
    if (url == null || !mounted) return;
    _urlController.text = url;
    _urlController.selection = TextSelection.collapsed(offset: url.length);
    setState(() {
      _fetching = true;
      _inputError = null;
      _outcome = null;
      _existingCard = null;
      _matchesExistingVersion = false;
      _cardSaved = false;
      _sourceLookupWarning = null;
    });
    try {
      // Fetch only — the Card is created explicitly by the user later.
      final outcome = await service.ingestUrl(url, createCard: false);
      CardContract? existing;
      var matchesExistingVersion = false;
      String? sourceLookupWarning;
      final sourceId = outcome.result.source?.sourceId;
      if (sourceId != null) {
        try {
          // Looking up an existing Source is only an optional de-duplication
          // hint. A temporarily unavailable repository must not turn an
          // already successful network / provider preview into "抓取失败".
          final record = await service.getSource(sourceId);
          existing = record?.card;
          final incomingHash = outcome.result.source?.contentHash;
          matchesExistingVersion = incomingHash != null &&
              record != null &&
              record.versions.any(
                (version) => version.contentHash == incomingHash,
              );
        } catch (_) {
          sourceLookupWarning = '预览已生成，但暂时无法核对这个来源是否已在卡片库。';
        }
      }
      if (!mounted) return;
      setState(() {
        _outcome = outcome;
        _existingCard = existing;
        _matchesExistingVersion = matchesExistingVersion;
        _sourceLookupWarning = sourceLookupWarning;
        _fetching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _inputError = _friendlyPreviewFailure(e);
      });
    }
  }

  Future<String?> _chooseUrl(SharedLinkInput input) async {
    if (input.urls.length == 1) return input.urls.single;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('link_import_url_picker'),
        title: const Text('选择要导入的链接'),
        content: SizedBox(
          width: 520,
          height: input.urls.length < 5 ? input.urls.length * 64.0 : 320,
          child: ListView.separated(
            itemCount: input.urls.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final candidate = input.urls[index];
              return ListTile(
                key: ValueKey('link_import_url_candidate_$index'),
                title: Text(
                  candidate,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: richTextCodeTextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.of(dialogContext).pop(candidate),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCard() async {
    final service = _service;
    final outcome = _outcome;
    if (service == null || outcome == null || _cardBusy) return;
    setState(() => _cardBusy = true);
    late final LinkIngestionOutcome finalOutcome;
    try {
      finalOutcome = await service.commitResult(outcome.result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cardBusy = false;
        _inputError = _friendlyCommitFailure(e);
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _outcome = finalOutcome;
      _existingCard = null;
      _matchesExistingVersion = true;
      _cardSaved = true;
      _cardBusy = false;
      _inputError = null;
      _sourceLookupWarning = null;
    });

    await _loadRecent();
  }

  void _openCardLibrary() {
    context.go(AppRoutes.cardLibrary);
  }

  Future<void> _goBack() async {
    final handled = await Navigator.of(context).maybePop();
    if (!handled && mounted) {
      context.go(AppRoutes.cardLibrary);
    }
  }

  void _openSavedDestination() {
    final source = _outcome?.result.source;
    if (source != null &&
        _outcome != null &&
        (_isStudyReady(_outcome!.result) ||
            _canOpenLimitedBilibiliPlayback(_outcome!.result))) {
      context.go(AppRoutes.sourceStudyPath(source.sourceId));
      return;
    }
    _openCardLibrary();
  }

  void _cancelPreview() {
    if (_cardBusy) return;
    setState(() {
      _outcome = null;
      _existingCard = null;
      _matchesExistingVersion = false;
      _cardSaved = false;
      _inputError = null;
      _sourceLookupWarning = null;
    });
    _urlFocusNode.requestFocus();
  }

  bool _isStudyReady(IngestionResult result) {
    return result.source?.mediaType == SourceMediaType.video &&
        (result.videoCapability == VideoCapabilityLevel.playbackStudy ||
            result.videoCapability == VideoCapabilityLevel.localized);
  }

  bool _canOpenLimitedBilibiliPlayback(IngestionResult result) {
    final source = result.source;
    return !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows &&
        source?.mediaType == SourceMediaType.video &&
        source?.provider == 'bilibili' &&
        result.videoCapability == VideoCapabilityLevel.linkOnly;
  }

  String _friendlyPreviewFailure(Object error) {
    if (_looksLikeClosedStorage(error)) {
      return '预览未完成：存储连接已失效。请重新打开桌面应用后再试。';
    }
    return '预览未完成。请检查网络后重试；若站点要求登录，应用会单独标明。';
  }

  String _friendlyCommitFailure(Object error) {
    if (_looksLikeClosedStorage(error)) {
      return '存入失败：存储连接已失效。请重新打开桌面应用后再保存；当前只是预览，尚未写入卡片库。';
    }
    return '存入失败，当前预览尚未写入卡片库。请稍后重试。';
  }

  bool _looksLikeClosedStorage(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('connection was closed') ||
        text.contains('database is closed') ||
        text.contains('try to send request') ||
        text.contains('isolate channel') && text.contains('closed');
  }

  // -----------------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.canvas,
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageTitle(
              title: '导入链接 / 视频',
              meta: '预览零写入 · 确认后提交当前结果',
              onBack: _goBack,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 640;
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 12 : 24,
                      4,
                      compact ? 12 : 24,
                      32,
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 960),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildFlowNote(),
                            const SizedBox(height: 12),
                            if (_storeError != null) _buildStoreError(),
                            _buildInputRow(compact: compact),
                            if (_inputError != null) _buildInputError(),
                            if (_fetching) _buildFetching(),
                            if (_outcome != null) _buildOutcome(_outcome!),
                            const SizedBox(height: 24),
                            if (_recentError != null)
                              _buildRecentRefreshError(),
                            _buildRecent(),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlowNote() {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: 18, color: tokens.actionSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '可直接粘贴分享文案或链接。先安全预览，再由你明确保存；确认时不会重新抓取。',
            style: whiteboardUiTextStyle(
              fontSize: 12,
              height: 1.5,
              color: tokens.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStoreError() {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.error.withValues(alpha: 0.52)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: tokens.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _storeError!,
              style: whiteboardUiTextStyle(
                color: tokens.error,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow({required bool compact}) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final input = FocusTraversalOrder(
      order: const NumericFocusOrder(10),
      child: TextField(
        key: const ValueKey('link_import_url_input'),
        controller: _urlController,
        focusNode: _urlFocusNode,
        enabled: _service != null && !_fetching && !_cardBusy,
        onSubmitted: (_) => _fetch(),
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.go,
        autocorrect: false,
        enableSuggestions: false,
        style: richTextCodeTextStyle(
          color: tokens.textPrimary,
          fontSize: 13,
        ),
        decoration: InputDecoration(
          hintText: '粘贴分享文案、网页或视频链接',
          hintStyle: whiteboardUiTextStyle(
            color: tokens.textFaint,
            fontSize: 13,
          ),
          filled: true,
          fillColor: tokens.surfaceRaised,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: tokens.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: tokens.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: tokens.action, width: 1.5),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: tokens.divider),
          ),
        ),
      ),
    );
    final button = FocusTraversalOrder(
      order: const NumericFocusOrder(20),
      child: FilledButton.icon(
        key: const ValueKey('link_import_fetch_button'),
        focusNode: _fetchFocusNode,
        onPressed: (_service == null || _fetching || _cardBusy) ? null : _fetch,
        icon: const Icon(Icons.travel_explore_rounded, size: 17),
        label: const Text('预览'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(112, 44),
          backgroundColor: tokens.action,
          foregroundColor: tokens.canvas,
          disabledBackgroundColor: tokens.actionSoft.withValues(alpha: 0.42),
          disabledForegroundColor: tokens.textMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: whiteboardUiTextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [input, const SizedBox(height: 8), button],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Expanded(child: input), const SizedBox(width: 8), button],
    );
  }

  Widget _buildInputError() {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        _inputError!,
        style: whiteboardUiTextStyle(
          color: tokens.error,
          fontSize: 12,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildFetching() {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.actionSoft.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              color: tokens.action,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '正在安全预览，当前不会写入卡片库。',
              style: whiteboardUiTextStyle(
                fontSize: 12,
                color: tokens.action,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutcome(LinkIngestionOutcome outcome) {
    final result = outcome.result;
    switch (result.status) {
      case IngestionStatus.ok:
        return _buildOkOutcome(outcome, result);
      case IngestionStatus.failed:
        return _buildStatusCard(
          icon: Icons.error_outline,
          statusLabel: '明确失败',
          title: '抓取失败',
          message: result.errorMessage ?? '未知错误',
          url: result.canonicalUrl,
          isError: true,
        );
      case IngestionStatus.needsAuth:
        return _buildStatusCard(
          icon: Icons.lock_outline,
          statusLabel: '需要授权',
          title: '需要登录或已被拒绝',
          message: result.errorMessage ?? '站点要求登录',
          url: result.canonicalUrl,
        );
      case IngestionStatus.partial:
        return _buildStatusCard(
          icon: Icons.warning_amber_rounded,
          statusLabel: '内容不完整',
          title: '内容不完整',
          message: result.errorMessage ?? '只拿到部分内容',
          url: result.canonicalUrl,
        );
      case IngestionStatus.unsupported:
        return _buildStatusCard(
          icon: Icons.warning_amber_rounded,
          statusLabel: '暂不支持',
          title: '暂不支持此链接',
          message: result.errorMessage ?? '普通链接抓取不支持该类型',
          url: result.canonicalUrl,
        );
    }
  }

  Widget _buildOkOutcome(
    LinkIngestionOutcome outcome,
    IngestionResult result,
  ) {
    final source = result.source!;
    final title = source.title;
    final description = result.metadata['description'] as String?;
    final excerpt = result.metadata['body_excerpt'] as String?;
    final images = (result.metadata['image_urls'] as List?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];
    final imageCount = images.length;
    final previewImage = result.metadata['og_image'] as String? ??
        (images.isEmpty ? null : images.first);
    final savedCard = outcome.card ?? _existingCard;
    final alreadyImported =
        savedCard != null && _matchesExistingVersion && !_cardSaved;
    final updateAvailable = savedCard != null && !_matchesExistingVersion;
    final studyReady = _isStudyReady(result);
    final limitedBilibiliPlayback = _canOpenLimitedBilibiliPlayback(result);
    final linkOnlyVideo = source.mediaType == SourceMediaType.video &&
        result.videoCapability == VideoCapabilityLevel.linkOnly;
    final capabilityLabel = studyReady
        ? '研读级就绪'
        : linkOnlyVideo
            ? '视频链接级保存'
            : '链接级保存';

    final Widget actionArea;
    if (alreadyImported || _cardSaved) {
      final card = savedCard ?? outcome.card;
      final updated = outcome.cardUpdated;
      actionArea = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInlineStatus(
            icon: Icons.check_circle_outline_rounded,
            label: updated ? '卡片已更新（内容有新版本）' : '已在卡片库',
            color: DesktopWorkspaceTokens.of(context).action,
          ),
          if (card != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                card.cardId,
                style: richTextCodeTextStyle(
                  color: DesktopWorkspaceTokens.of(context).textFaint,
                  fontSize: 11,
                ),
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _openSavedDestination,
            icon: Icon(
              studyReady || limitedBilibiliPlayback
                  ? Icons.play_circle_outline
                  : Icons.library_books_outlined,
              size: 16,
            ),
            label: Text(
              studyReady
                  ? '打开视频研读'
                  : limitedBilibiliPlayback
                  ? '打开视频播放（时间研读受限）'
                  : '打开卡片库',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: DesktopWorkspaceTokens.of(context).action,
              side: BorderSide(
                color: DesktopWorkspaceTokens.of(context).action,
              ),
              minimumSize: const Size(112, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      );
    } else {
      actionArea = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FocusTraversalOrder(
            order: const NumericFocusOrder(30),
            child: OutlinedButton(
              key: const ValueKey('link_import_cancel_preview'),
              focusNode: _cancelPreviewFocusNode,
              onPressed: _cardBusy ? null : _cancelPreview,
              style: _secondaryButtonStyle(),
              child: const Text('取消预览'),
            ),
          ),
          FocusTraversalOrder(
            order: const NumericFocusOrder(40),
            child: FilledButton.icon(
              key: const ValueKey('link_import_commit_button'),
              focusNode: _commitFocusNode,
              onPressed: _cardBusy ? null : _saveCard,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: Text(
                _cardBusy
                    ? '正在存入…'
                    : updateAvailable
                        ? '确认内容更新'
                        : studyReady
                            ? '保存'
                            : '存入卡片库',
              ),
              style: _primaryButtonStyle(),
            ),
          ),
        ],
      );
    }

    final tokens = DesktopWorkspaceTokens.of(context);
    return Container(
      key: const ValueKey('link_import_preview_panel'),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildInlineStatus(
                  icon: Icons.check_circle_outline_rounded,
                  label: '预览成功',
                  color: tokens.action,
                ),
              ),
              _providerChip(source.provider),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: whiteboardUiTextStyle(
              color: tokens.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            result.canonicalUrl,
            style: richTextCodeTextStyle(
              color: tokens.textFaint,
              fontSize: 11,
              height: 1.45,
            ),
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              description,
              style: whiteboardUiTextStyle(
                color: tokens.textMuted,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ],
          if (source.metadata['site_name'] != null ||
              source.metadata['author'] != null) ...[
            const SizedBox(height: 8),
            Text(
              [source.metadata['site_name'], source.metadata['author']]
                  .whereType<String>()
                  .where((value) => value.isNotEmpty)
                  .join(' · '),
              style: whiteboardUiTextStyle(
                color: tokens.textFaint,
                fontSize: 11,
              ),
            ),
          ],
          if (excerpt != null && excerpt.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                excerpt,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: whiteboardUiTextStyle(
                  color: tokens.textMuted,
                  fontSize: 13,
                  height: 1.55,
                ),
              ),
            ),
          ],
          if (previewImage != null && previewImage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.image_outlined, color: tokens.textFaint, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '主图候选（未加载） · $previewImage',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: richTextCodeTextStyle(
                      color: tokens.textFaint,
                      fontSize: 10,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            [
              if (result.hasBody) '正文可用',
              if (source.mediaType == SourceMediaType.video) '视频来源',
              if (imageCount > 0) '$imageCount 张图片',
              if (source.mimeType != null) source.mimeType!,
            ].join(' · '),
            style: whiteboardUiTextStyle(
              color: tokens.textFaint,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 14),
          _buildCapabilityState(
            label: capabilityLabel,
            studyReady: studyReady,
          ),
          if (_sourceLookupWarning != null) ...[
            const SizedBox(height: 10),
            _buildInlineNotice(
              icon: Icons.storage_outlined,
              message: _sourceLookupWarning!,
            ),
          ],
          if (updateAvailable) ...[
            const SizedBox(height: 12),
            Text(
              '已导入过这个链接，但网页内容发生了变化。确认后会为同一来源新增版本，不会复制卡片。',
              style: whiteboardUiTextStyle(
                color: tokens.focus,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 14),
          actionArea,
        ],
      ),
    );
  }

  Widget _buildCapabilityState({
    required String label,
    required bool studyReady,
  }) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: tokens.actionSoft.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            studyReady ? Icons.playlist_add_check_rounded : Icons.link_rounded,
            size: 17,
            color: tokens.action,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: whiteboardUiTextStyle(
                    fontSize: 12,
                    color: tokens.action,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  studyReady
                      ? '来源可进入研读视图；字幕、时间轴与 Anchor 仍按实际加载结果确认。'
                      : '保存 canonical URL 与当前 SourceVersion；缺失的正文、封面或字幕不会被补造。',
                  style: whiteboardUiTextStyle(
                    fontSize: 11,
                    height: 1.45,
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineStatus({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: whiteboardUiTextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInlineNotice({
    required IconData icon,
    required String message,
  }) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: tokens.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: whiteboardUiTextStyle(
                color: tokens.textMuted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _primaryButtonStyle() {
    final tokens = DesktopWorkspaceTokens.of(context);
    return FilledButton.styleFrom(
      minimumSize: const Size(132, 36),
      backgroundColor: tokens.action,
      foregroundColor: tokens.canvas,
      disabledBackgroundColor: tokens.actionSoft.withValues(alpha: 0.42),
      disabledForegroundColor: tokens.textMuted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: whiteboardUiTextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  ButtonStyle _secondaryButtonStyle() {
    final tokens = DesktopWorkspaceTokens.of(context);
    return OutlinedButton.styleFrom(
      minimumSize: const Size(96, 36),
      foregroundColor: tokens.textMuted,
      side: BorderSide(color: tokens.divider),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: whiteboardUiTextStyle(fontSize: 13),
    );
  }

  Widget _providerChip(String? provider) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tokens.divider),
      ),
      child: Text(
        provider ?? 'web',
        style: richTextCodeTextStyle(
          color: tokens.textMuted,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildStatusCard({
    required IconData icon,
    required String statusLabel,
    required String title,
    required String message,
    required String url,
    bool isError = false,
  }) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final statusColor = isError ? tokens.error : tokens.focus;
    return Container(
      key: const ValueKey('link_import_status_panel'),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: statusColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusLabel,
                  style: whiteboardUiTextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: whiteboardUiTextStyle(
                    color: tokens.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: whiteboardUiTextStyle(
                    color: tokens.textMuted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  url,
                  style: richTextCodeTextStyle(
                    color: tokens.textFaint,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentRefreshError() {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Container(
      key: const ValueKey('link_import_recent_error'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.focus.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.focus.withValues(alpha: 0.42)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sync_problem_rounded, size: 18, color: tokens.focus),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _recentError!,
              style: whiteboardUiTextStyle(
                color: tokens.textMuted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecent() {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '最近导入',
              style: whiteboardUiTextStyle(
                color: tokens.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${_recent.length} 项',
              style: whiteboardUiTextStyle(
                color: tokens.textFaint,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_recent.isEmpty)
          Text(
            '还没有导入记录。抓取结果确认后，点击「存入卡片库」才会创建卡片。',
            style: whiteboardUiTextStyle(
              color: tokens.textFaint,
              fontSize: 12,
              height: 1.5,
            ),
          )
        else
          ..._recent.map(_buildRecentTile),
      ],
    );
  }

  Widget _buildRecentTile(_RecentImport item) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.divider),
      ),
      child: Row(
        children: [
          Icon(
            Icons.link_outlined,
            color: tokens.textFaint,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.card.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: whiteboardUiTextStyle(
                    color: tokens.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (item.canonicalUrl.isNotEmpty)
                  Text(
                    item.canonicalUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: richTextCodeTextStyle(
                      color: tokens.textFaint,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${item.versionCount} 版',
                style: richTextCodeTextStyle(
                  color: tokens.textMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatDate(item.createdAt),
                style: richTextCodeTextStyle(
                  color: tokens.textFaint,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}
