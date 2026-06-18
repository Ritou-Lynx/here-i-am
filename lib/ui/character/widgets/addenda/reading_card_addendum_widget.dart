import 'package:flutter/material.dart';

import 'package:memex/data/services/conversation_capture_service.dart';
import 'package:memex/data/services/reading/reading_fetch_coordinator.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';

/// Inline preview card for a saved reading item (article from 小红书,
/// 微信公众号, etc).
///
/// **In-chat version is intentionally minimal.** The full card (with tags,
/// edit / discuss buttons, source operations, etc.) lives in the future
/// Memory detail view. Inside a chat bubble we only show the
/// "presentation module" itself — cover + title + author/source + excerpt
/// — because the user is already in the chat context. If they want to
/// discuss it they just type. Buttons inside a chat bubble are an
/// anti-pattern for a relationship-oriented product.
///
/// Layout is horizontal (small cover on the left, text stack on the right)
/// to fit comfortably inside a chat bubble that's at most ~320px wide.
///
/// Addendum payload schema:
///   {
///     "type": "reading_card",
///     "entityId": "...",          // SharedLifeEntity id (reading_item)
///     "title": "...",              // Placeholder title from share parser
///     "source": "xiaohongshu",     // Platform identifier
///     "coverUrl": "...",           // Optional placeholder cover
///   }
class ReadingCardAddendumWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool isCharacterBubble;

  const ReadingCardAddendumWidget({
    super.key,
    required this.data,
    required this.isCharacterBubble,
  });

  @override
  State<ReadingCardAddendumWidget> createState() =>
      _ReadingCardAddendumWidgetState();
}

class _ReadingCardAddendumWidgetState extends State<ReadingCardAddendumWidget> {
  SharedLifeEntitySnapshot? _liveEntity;
  bool _querying = false;

  String get _entityId => (widget.data['entityId'] as String?) ?? '';

  @override
  void initState() {
    super.initState();
    _refreshEntity();
    if (ReadingFetchCoordinator.isInitialized) {
      ReadingFetchCoordinator.instance.entityFetchUpdates
          .addListener(_onFetchUpdate);
    }
  }

  @override
  void dispose() {
    if (ReadingFetchCoordinator.isInitialized) {
      ReadingFetchCoordinator.instance.entityFetchUpdates
          .removeListener(_onFetchUpdate);
    }
    super.dispose();
  }

  void _onFetchUpdate() {
    final updatedId =
        ReadingFetchCoordinator.instance.entityFetchUpdates.value;
    if (updatedId == _entityId) {
      _refreshEntity();
    }
  }

  Future<void> _refreshEntity() async {
    if (_querying) return;
    final id = _entityId;
    if (id.isEmpty || id.startsWith('pending-') || id.startsWith('debug-')) {
      return;
    }
    if (!ConversationCaptureService.isInitialized) return;
    _querying = true;
    try {
      final detail = await ConversationCaptureService.instance.sharedLifeMemory
          .getEntityDetail(id);
      if (!mounted) return;
      if (detail != null && detail.entity.entityType == 'reading_item') {
        setState(() => _liveEntity = detail.entity);
      }
    } finally {
      _querying = false;
    }
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'xiaohongshu':
        return '小红书';
      case 'wechat':
      case 'wechat_mp':
        return '微信公众号';
      case 'web':
        return '网页';
      default:
        return source;
    }
  }

  String _fetchStatusOf(SharedLifeEntitySnapshot? entity) {
    if (entity == null) return 'pending';
    final raw = entity.state['fetch_status'];
    if (raw is String && raw.isNotEmpty) return raw;
    return 'pending';
  }

  @override
  Widget build(BuildContext context) {
    // Merge addendum payload (placeholder) with live entity state. Live
    // values win when present.
    final entity = _liveEntity;
    final state = entity?.state ?? const <String, dynamic>{};

    final placeholderTitle =
        (widget.data['title'] as String?)?.trim() ?? '未命名内容';
    final title = (entity?.title.trim().isNotEmpty == true
        ? entity!.title.trim()
        : placeholderTitle);

    final source = (state['platform'] as String?) ??
        (widget.data['source'] as String?) ??
        'web';
    final author = (state['author'] as String?)?.trim();
    final coverUrl = (state['cover_url'] as String?)?.trim() ??
        (widget.data['coverUrl'] as String?)?.trim();
    final excerpt = (state['content_excerpt'] as String?)?.trim();
    final fetchStatus = _fetchStatusOf(entity);

    final hasCover = coverUrl != null && coverUrl.isNotEmpty;
    final meta = _metaLine(source, author);

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1D24).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE4D6BD).withValues(alpha: 0.18),
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasCover)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF101217),
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFFF2ECE0),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      style: const TextStyle(
                        color: Color(0xFF9E9A94),
                        fontSize: 11,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (excerpt != null && excerpt.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      excerpt,
                      style: const TextStyle(
                        color: Color(0xFFB8B0A3),
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ] else if (_statusHint(fetchStatus) != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _statusHint(fetchStatus)!,
                      style: TextStyle(
                        color: fetchStatus == 'failed'
                            ? const Color(0xFFD08585)
                            : const Color(0xFFE4D6BD),
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _metaLine(String source, String? author) {
    final pieces = <String>[
      _sourceLabel(source),
      if (author != null && author.isNotEmpty) author,
    ];
    return pieces.join(' · ');
  }

  String? _statusHint(String fetchStatus) {
    switch (fetchStatus) {
      case 'pending':
        return '正在读…';
      case 'failed':
        return '内容加载失败';
      case 'unsupported':
        return '该平台暂未支持抓取';
      default:
        return null;
    }
  }
}
