import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/agent/companion_agent/companion_agent.dart';
import 'package:memex/data/services/book/book_library_service.dart';
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

  // Chat state
  String _characterId = '';
  bool _chatOpen = false;
  bool _sending = false;
  String _reply = '';
  final TextEditingController _input = TextEditingController();
  final ScrollController _chatScroll = ScrollController();
  List<PersonaChatMessage> _messages = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _progressThrottle?.cancel();
    _scroll.dispose();
    _input.dispose();
    _chatScroll.dispose();
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
        _loadingContent = false;
      });
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
    if (number < 1 || number > _chapters.length) return;
    _scroll.jumpTo(0);
    _loadChapterContent(number);
  }

  Future<void> _pickChapter() async {
    if (_chapters.isEmpty) return;
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
                child: Text('目录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              );
            }
            final ch = _chapters[i - 1];
            return ListTile(
              title: Text(ch.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: ch.number == _currentChapter ? const Icon(Icons.check, size: 18) : null,
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
      final res = await UserStorage.getAgentLLMResources(
        AgentDefinitions.companionAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      String full = '';
      await for (final chunk in CompanionAgent.chat(
        client: res.client,
        modelConfig: res.modelConfig,
        userId: userId,
        characterId: _characterId,
        userMessage: text,
        debugErrorOutput: true,
      )) {
        if (!mounted) return;
        full = chunk;
        setState(() => _reply = chunk);
        _scrollChatToBottom();
      }
      await PersonaChatService.instance.addUserMessage(_characterId, text);
      if (full.trim().isNotEmpty) {
        await PersonaChatService.instance
            .addCharacterMessage(_characterId, full, isRead: true);
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
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
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
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                controller: _chatScroll,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            Text('和林埃聊这一段（${_chapterTitle()}）'),
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
        body: Center(child: Padding(
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
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: SelectableText(
                        _content,
                        style: const TextStyle(
                          fontSize: 17,
                          height: 1.8,
                          letterSpacing: 0.3,
                        ),
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
