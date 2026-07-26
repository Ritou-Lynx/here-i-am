import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:memex/data/services/book/book_library_service.dart';
import 'package:memex/data/services/book/book_remote_service.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/book/book_reader_screen.dart';
import 'package:memex/utils/user_storage.dart';

/// Book co-reading bookshelf. Entry screen for the reading feature.
///
/// Shows imported books with progress, allows TXT import via file picker,
/// and server configuration (same Tailscale model as comic).
class BookLibraryScreen extends StatefulWidget {
  const BookLibraryScreen({super.key});

  @override
  State<BookLibraryScreen> createState() => _BookLibraryScreenState();
}

class _BookLibraryScreenState extends State<BookLibraryScreen> {
  List<Book> _books = const [];
  bool _loading = true;
  bool _configured = false;
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final remote = BookRemoteService(db: AppDatabase.instance);
      final configured = await remote.isConfigured();
      final books = await BookLibraryService.instance.getLibrary();
      if (!mounted) return;
      setState(() {
        _books = books;
        _configured = configured;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<String> _primaryCharacterId() async {
    final userId = await UserStorage.getUserId();
    if (userId == null) return '';
    final chars = await CharacterService.instance.getAllCharacters(userId);
    if (chars.isEmpty) return '';
    final pick = chars.firstWhere(
      (c) => c.enabled && c.isPrimaryCompanion,
      orElse: () => chars.firstWhere((c) => c.enabled, orElse: () => chars.first),
    );
    return pick.id;
  }

  Future<void> _importTxt() async {
    if (!_configured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先配置书籍服务地址（右上角）')),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return;

    setState(() => _importing = true);
    try {
      final charId = await _primaryCharacterId();
      final book = await BookLibraryService.instance.importTxt(
        Uint8List.fromList(bytes),
        file.name,
        characterId: charId.isEmpty ? 'unknown' : charId,
      );
      if (!mounted) return;
      if (book != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入成功：${book.title}（${book.chapterCount} 章）')),
        );
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入失败，请检查服务连接')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入出错：$e')),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _configureServer() async {
    final remote = BookRemoteService(db: AppDatabase.instance);
    final cur = await remote.getBaseUrl();
    final ctrl = TextEditingController(text: cur);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('书籍服务地址'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('填 Tailscale HTTPS 地址，例如 https://xxx.ts.net:8444。'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存并测试'),
          ),
        ],
      ),
    );
    if (url == null) return;
    await remote.saveBaseUrl(url);
    final err = await remote.testConnection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(url.isEmpty
            ? '已清空。'
            : (err == null ? '连接成功 ✓' : '连接失败：$err')),
      ),
    );
    _load();
  }

  Future<void> _openBook(Book book) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookReaderScreen(bookId: book.id, bookTitle: book.title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('共读书架'),
        actions: [
          IconButton(
            icon: Icon(_configured ? Icons.cloud_done : Icons.cloud_off),
            tooltip: '书籍服务地址',
            onPressed: _configureServer,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _importing ? null : _importTxt,
        child: _importing
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _books.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 80),
                        Center(
                          child: Column(
                            children: [
                              Icon(Icons.menu_book, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text(
                                _configured ? '点右下角 + 导入一本 TXT' : '先配置书籍服务地址，再导入 TXT',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      itemCount: _books.length,
                      itemBuilder: (_, i) {
                        final book = _books[i];
                        return ListTile(
                          leading: const Icon(Icons.menu_book),
                          title: Text(book.title),
                          subtitle: Text(
                            '${book.chapterCount} 章 · ${(book.totalChars / 10000).toStringAsFixed(1)} 万字'
                            '${book.author.isNotEmpty ? ' · ${book.author}' : ''}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                tooltip: '删除',
                                onPressed: () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('删除书籍'),
                                      content: Text('确定要删除「${book.title}」吗？'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    await BookLibraryService.instance.removeBook(book.id);
                                    if (!mounted) return;
                                    _load();
                                  }
                                },
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () => _openBook(book),
                        );
                      },
                    ),
    );
  }
}
