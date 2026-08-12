import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:memex/agent/companion_agent/companion_agent.dart';
import 'package:memex/data/services/book/book_annotation_service.dart';
import 'package:memex/data/services/book/book_library_service.dart';
import 'package:memex/data/services/book/co_reading_note_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/user_storage.dart';

/// Text book reader with co-reading chat panel.
///
/// UX: vertical scroll reading, auto chapter continuation, TOC sidebar,
/// progress memory, and a bottom chat bar to discuss with the companion
/// who knows the current chapter context.
class BookReaderScreen extends StatefulWidget {
  final String bookId;
  final String bookTitle;

  const BookReaderScreen({
    super.key,
    required this.bookId,
    required this.bookTitle,
  });

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen> {
  List<BookChapter> _chapters = const [];
  int _currentChapter = 1;
  String _content = '';
  bool _loadingContent = true;
  String? _error;

  final ScrollController _scroll = ScrollController();
  Timer? _progressThrottle;
  late final BookAnnotationService _annotationService;
  List<BookAnnotation> _annotations = const [];
  final Map<String, TapGestureRecognizer> _annotationRecognizers = {};

  // Chat state
  String _characterId = '';
  bool _chatOpen = false;
  bool _sending = false;
  String _reply = '';
  final TextEditingController _input = TextEditingController();
  final ScrollController _chatScroll = ScrollController();
  List<PersonaChatMessage> _messages = const [];
  String? _coReadingSessionId;
  String _coReadingContinuityContext = '';

  @override
  void initState() {
    super.initState();
    _annotationService = BookAnnotationService(db: AppDatabase.instance);
    _load();
  }

  @override
  void dispose() {
    final sessionId = _coReadingSessionId;
    if (sessionId != null && CoReadingNoteService.isInitialized) {
      unawaited(CoReadingNoteService.instance.finishSession(sessionId));
    }
    _progressThrottle?.cancel();
    _scroll.dispose();
    _input.dispose();
    _chatScroll.dispose();
    for (final recognizer in _annotationRecognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final lib = BookLibraryService.instance;
      final book = await lib.getBook(widget.bookId);
      final chapters = await lib.getChapters(widget.bookId);
      final progress = await lib.getProgress(widget.bookId);

      final startChapter = progress?.chapterNumber ?? 1;

      if (!mounted) return;
      setState(() {
        _chapters = chapters;
        _currentChapter = startChapter;
        _characterId = book?.characterId ?? '';
      });

      await _loadChapterContent(startChapter);
      await _loadMessages();

      await _beginCoReadingSession();

      // Restore scroll position
      if (progress != null && progress.scrollRatio > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            final max = _scroll.position.maxScrollExtent;
            _scroll.jumpTo(max * progress.scrollRatio);
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载失败: $e');
    }
  }

  Future<void> _loadChapterContent(int number) async {
    setState(() {
      _loadingContent = true;
      _currentChapter = number;
    });
    try {
      final content = await BookLibraryService.instance
          .getChapterContent(widget.bookId, number);
      if (!mounted) return;
      setState(() {
        _content = content ?? '（无法加载章节内容）';
      });
      await _loadAnnotations(number);
      if (mounted) setState(() => _loadingContent = false);
      // Record progress
      BookLibraryService.instance.recordProgress(
        bookId: widget.bookId,
        chapterNumber: number,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _content = '加载出错: $e';
        _loadingContent = false;
      });
    }
  }

  Future<void> _loadAnnotations(int chapterNumber) async {
    final items = await _annotationService.listForChapter(
      bookId: widget.bookId,
      chapterNumber: chapterNumber,
    );
    if (!mounted || chapterNumber != _currentChapter) return;
    for (final recognizer in _annotationRecognizers.values) {
      recognizer.dispose();
    }
    _annotationRecognizers.clear();
    for (final annotation in items) {
      _annotationRecognizers[annotation.id] = TapGestureRecognizer()
        ..onTap = () => _editAnnotation(annotation);
    }
    setState(() => _annotations = items);
  }

  Future<String?> _promptForNote({
    required String quote,
    String initialNote = '',
  }) async {
    final controller = TextEditingController(text: initialNote);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '写下这段带给你的想法',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x14737B46),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                quote,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.55, color: Color(0xFF4D5649)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 7,
              decoration: const InputDecoration(
                hintText: '可以只写一句，也可以慢慢展开……',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(sheetContext, controller.text),
              child: const Text('保存批注'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _createAnnotation(
    TextSelection selection, {
    required bool withNote,
  }) async {
    ContextMenuController.removeAny();
    if (!selection.isValid || selection.isCollapsed || _content.isEmpty) return;
    final start = selection.start.clamp(0, _content.length);
    final end = selection.end.clamp(0, _content.length);
    if (start >= end) return;
    final quote = _content.substring(start, end);
    final note = withNote ? await _promptForNote(quote: quote) : '';
    if (withNote && note == null) return;

    try {
      await _annotationService.create(
        bookId: widget.bookId,
        chapterNumber: _currentChapter,
        chapterContent: _content,
        startOffset: start,
        endOffset: end,
        note: note ?? '',
      );
      await _loadAnnotations(_currentChapter);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(withNote ? '批注已保存' : '已划线')),
      );
    } on BookAnnotationOverlapException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这段文字已经有划线了，可以点它修改批注')),
      );
    }
  }

  Widget _buildSelectionMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final selection = editableTextState.textEditingValue.selection;
    final items = List<ContextMenuButtonItem>.of(
      editableTextState.contextMenuButtonItems,
    );
    if (selection.isValid && !selection.isCollapsed) {
      items.insertAll(0, [
        ContextMenuButtonItem(
          label: '划线',
          onPressed: () => unawaited(
            _createAnnotation(selection, withNote: false),
          ),
        ),
        ContextMenuButtonItem(
          label: '批注',
          onPressed: () => unawaited(
            _createAnnotation(selection, withNote: true),
          ),
        ),
      ]);
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  TextSpan _buildAnnotatedText() {
    if (_annotations.isEmpty) return TextSpan(text: _content);
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final annotation in _annotations) {
      final start = annotation.startOffset.clamp(cursor, _content.length);
      final end = annotation.endOffset.clamp(start, _content.length);
      if (start > cursor) {
        spans.add(TextSpan(text: _content.substring(cursor, start)));
      }
      if (end > start) {
        spans.add(TextSpan(
          text: _content.substring(start, end),
          style: const TextStyle(
            backgroundColor: Color(0x667F8A45),
            decoration: TextDecoration.underline,
            decorationColor: Color(0xFF737B46),
            decorationThickness: 1.2,
          ),
          recognizer: _annotationRecognizers[annotation.id],
        ));
      }
      cursor = end;
    }
    if (cursor < _content.length) {
      spans.add(TextSpan(text: _content.substring(cursor)));
    }
    return TextSpan(children: spans);
  }

  Future<void> _editAnnotation(BookAnnotation annotation) async {
    if (!mounted) return;
    final controller = TextEditingController(text: annotation.note);
    final action = await showModalBottomSheet<_AnnotationEditAction>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              annotation.quote,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, height: 1.6),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 7,
              decoration: const InputDecoration(
                hintText: '写下感想；留空也可以只保留划线',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.pop(
                    sheetContext,
                    const _AnnotationEditAction.delete(),
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    sheetContext,
                    _AnnotationEditAction.save(controller.text),
                  ),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (action == null) return;
    if (action.delete) {
      await _annotationService.delete(annotation.id);
    } else {
      await _annotationService.updateNote(annotation.id, action.note ?? '');
    }
    await _loadAnnotations(_currentChapter);
  }

  Future<void> _openBookNotes() async {
    final annotations = await _annotationService.listForBook(widget.bookId);
    if (!mounted) return;
    if (annotations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有划线或批注。长按正文选中文字即可开始。')),
      );
      return;
    }
    final selected = await showModalBottomSheet<BookAnnotation>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.76,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '本书笔记',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: annotations.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final item = annotations[index];
                    return ListTile(
                      title: Text(
                        item.quote,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        item.note.isEmpty
                            ? '第 ${item.chapterNumber} 章 · 仅划线'
                            : '第 ${item.chapterNumber} 章 · ${item.note}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(sheetContext, item),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await _jumpToAnnotation(selected);
  }

  Future<void> _jumpToAnnotation(BookAnnotation annotation) async {
    if (annotation.chapterNumber != _currentChapter) {
      await _switchChapter(annotation.chapterNumber);
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || _content.isEmpty) return;
      final ratio = (annotation.startOffset / _content.length).clamp(0.0, 1.0);
      _scroll.animateTo(
        _scroll.position.maxScrollExtent * ratio,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _loadMessages() async {
    if (_characterId.isEmpty) return;
    try {
      final msgs = await PersonaChatService.instance
          .getMessages(_characterId, limit: 50);
      if (!mounted) return;
      setState(() => _messages = msgs.reversed.toList());
      _scrollChatToBottom();
    } catch (_) {}
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(
          _chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onScroll() {
    if (_progressThrottle?.isActive ?? false) return;
    _progressThrottle = Timer(const Duration(milliseconds: 500), () {
      if (!_scroll.hasClients) return;
      final ratio = _scroll.position.maxScrollExtent > 0
          ? _scroll.position.pixels / _scroll.position.maxScrollExtent
          : 0.0;
      BookLibraryService.instance.recordProgress(
        bookId: widget.bookId,
        chapterNumber: _currentChapter,
        scrollRatio: ratio,
      );
      // Auto-advance: if scrolled to very bottom, load next chapter
      if (ratio > 0.98 && _currentChapter < _chapters.length) {
        _goToChapter(_currentChapter + 1);
      }
    });
  }

  void _goToChapter(int number) {
    if (_sending || number < 1 || number > _chapters.length) return;
    unawaited(_switchChapter(number));
  }

  Future<void> _switchChapter(int number) async {
    await _finishCoReadingSession();
    _scroll.jumpTo(0);
    await _loadChapterContent(number);
    await _beginCoReadingSession();
  }

  Future<void> _beginCoReadingSession() async {
    if (!CoReadingNoteService.isInitialized || _characterId.isEmpty) return;
    final handle = await CoReadingNoteService.instance.startBookSession(
      bookId: widget.bookId,
      bookTitle: widget.bookTitle,
      characterId: _characterId,
      chapterNumber: _currentChapter,
      chapterTitle: _chapterTitle(),
    );
    if (!mounted) {
      unawaited(CoReadingNoteService.instance.finishSession(handle.id));
      return;
    }
    _coReadingSessionId = handle.id;
    _coReadingContinuityContext = handle.continuityContext;
  }

  Future<void> _finishCoReadingSession() async {
    final sessionId = _coReadingSessionId;
    _coReadingSessionId = null;
    _coReadingContinuityContext = '';
    if (sessionId == null || !CoReadingNoteService.isInitialized) return;
    await CoReadingNoteService.instance.finishSession(
      sessionId,
      processNow: false,
    );
  }

  Future<void> _pickChapter() async {
    if (_sending || _chapters.isEmpty) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _chapters.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Text('目录',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              );
            }
            final ch = _chapters[i - 1];
            return ListTile(
              title:
                  Text(ch.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: ch.number == _currentChapter
                  ? const Icon(Icons.check, size: 18)
                  : null,
              onTap: () => Navigator.pop(ctx, ch.number),
            );
          },
        ),
      ),
    );
    if (picked != null && picked != _currentChapter) {
      _goToChapter(picked);
    }
  }

  // ── Chat ───────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || _characterId.isEmpty) return;
    _input.clear();
    setState(() => _sending = true);

    final userId = await UserStorage.getUserId();
    if (userId == null) {
      if (mounted) setState(() => _sending = false);
      return;
    }

    final userMsg = PersonaChatMessage(
      id: -1,
      characterId: _characterId,
      isFromCharacter: false,
      content: text,
      factId: null,
      isRead: true,
      timestamp: DateTime.now(),
      messageType: 'chat',
      attachmentsJson: null,
    );
    setState(() {
      _messages = [..._messages, userMsg];
      _reply = '';
    });
    _scrollChatToBottom();

    try {
      final userMessageId =
          await PersonaChatService.instance.addUserMessage(_characterId, text);
      final sessionId = _coReadingSessionId;
      if (sessionId != null && CoReadingNoteService.isInitialized) {
        await CoReadingNoteService.instance.recordMessages(
          sessionId: sessionId,
          messageIds: [userMessageId],
        );
      }
      final res = await UserStorage.getAgentLLMResources(
        AgentDefinitions.companionAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      if (CoReadingNoteService.isInitialized) {
        _coReadingContinuityContext =
            await CoReadingNoteService.instance.buildContinuityContext(
          workType: 'book',
          workId: widget.bookId,
        );
      }
      String full = '';
      await for (final chunk in CompanionAgent.chat(
        client: res.client,
        modelConfig: res.modelConfig,
        userId: userId,
        characterId: _characterId,
        userMessage: text,
        recallQuery: text,
        userMessageId: userMessageId,
        turnContextReminder: _coReadingContinuityContext,
        debugErrorOutput: true,
      )) {
        if (!mounted) return;
        full = chunk;
        setState(() => _reply = chunk);
        _scrollChatToBottom();
      }
      if (full.trim().isNotEmpty) {
        final characterMessageId = await PersonaChatService.instance
            .addCharacterMessage(_characterId, full, isRead: true);
        if (sessionId != null && CoReadingNoteService.isInitialized) {
          await CoReadingNoteService.instance.recordMessages(
            sessionId: sessionId,
            messageIds: [characterMessageId],
          );
        }
      }
      await _loadMessages();
      if (mounted) setState(() => _reply = '');
    } catch (e) {
      if (!mounted) return;
      setState(() => _reply = '[出错] $e');
      await _loadMessages();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  Widget _buildBubble(String text, bool fromCharacter) {
    return Align(
      alignment: fromCharacter ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: fromCharacter ? Colors.white : const Color(0xFFD8F5B4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SelectableText(text, style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  Widget _buildChatFooter() {
    if (_chatOpen) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.4,
        decoration: const BoxDecoration(
          color: Color(0xFFF4F4F6),
          border: Border(top: BorderSide(color: Color(0xFFDDDDDD))),
        ),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.expand_more),
                  onPressed: () => setState(() => _chatOpen = false),
                ),
                Expanded(
                  child: Text(
                    '和林埃聊 · ${_chapterTitle()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                controller: _chatScroll,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: _messages.length + (_reply.isNotEmpty ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == _messages.length) return _buildBubble(_reply, true);
                  final m = _messages[i];
                  return _buildBubble(m.content, m.isFromCharacter);
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: '聊聊这一段…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return InkWell(
      onTap: () => setState(() => _chatOpen = true),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: const BoxDecoration(
          color: Color(0xFFF4F4F6),
          border: Border(top: BorderSide(color: Color(0xFFDDDDDD))),
        ),
        child: Row(
          children: [
            const Icon(Icons.chat_bubble_outline, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '和林埃聊这一段（${_chapterTitle()}）',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _chapterTitle() {
    if (_chapters.isEmpty) return '第 $_currentChapter 章';
    final ch = _chapters.firstWhere(
      (c) => c.number == _currentChapter,
      orElse: () => _chapters.first,
    );
    return ch.title;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.bookTitle)),
        body: Center(
            child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        )),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.bookTitle} · $_currentChapter/${_chapters.length}',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_outline),
            tooltip: '本书笔记',
            onPressed: _openBookNotes,
          ),
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: '目录',
            onPressed: _pickChapter,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loadingContent
                ? const Center(child: CircularProgressIndicator())
                : NotificationListener<ScrollNotification>(
                    onNotification: (_) {
                      _onScroll();
                      return false;
                    },
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      child: SelectableText.rich(
                        _buildAnnotatedText(),
                        style: const TextStyle(
                          fontSize: 17,
                          height: 1.8,
                          letterSpacing: 0.3,
                        ),
                        contextMenuBuilder: _buildSelectionMenu,
                      ),
                    ),
                  ),
          ),
          _buildChatFooter(),
        ],
      ),
    );
  }
}

class _AnnotationEditAction {
  const _AnnotationEditAction.save(this.note) : delete = false;
  const _AnnotationEditAction.delete()
      : delete = true,
        note = null;

  final bool delete;
  final String? note;
}
