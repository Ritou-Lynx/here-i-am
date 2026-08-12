import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/data/services/book/book_library_service.dart';
import 'package:memex/data/services/book/book_remote_service.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/comic/comic_library_service.dart';
import 'package:memex/data/services/comic/comic_reading_progress_service.dart';
import 'package:memex/data/services/comic/comic_remote_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/book/book_reader_screen.dart';
import 'package:memex/ui/comic/comic_reader_screen.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/utils/user_storage.dart';

enum ReadingShelfFilter { reading, all, novels, comics }

enum ReadingShelfView { list, covers }

/// One visual shelf over the existing Books and ComicMangas stores.
class UnifiedReadingScreen extends StatefulWidget {
  const UnifiedReadingScreen({super.key});

  @override
  State<UnifiedReadingScreen> createState() => _UnifiedReadingScreenState();
}

class _UnifiedReadingScreenState extends State<UnifiedReadingScreen> {
  static const _rain = 'assets/images/雨玻璃.jpg';
  static const _ink = Color(0xFF293025);
  static const _muted = Color(0xFF667061);
  static const _accent = Color(0xFF737B46);
  static const _fog = Color(0xEAF7F5ED);

  List<_ShelfItem> _items = const [];
  ReadingShelfFilter _filter = ReadingShelfFilter.reading;
  ReadingShelfView _view = ReadingShelfView.covers;
  bool _loading = true;
  bool _busy = false;
  bool _bookConfigured = false;
  bool _comicConfigured = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDatabase.instance;
    final results = await Future.wait([
      BookLibraryService.instance.getLibrary(),
      ComicLibraryService.instance.getLibrary(),
      db.select(db.bookReadingProgress).get(),
      db.select(db.comicReadingProgress).get(),
      BookRemoteService(db: db).isConfigured(),
      ComicRemoteService(db: db).isConfigured(),
    ]);
    final books = results[0] as List<Book>;
    final comics = results[1] as List<ComicManga>;
    final bookProgress = {
      for (final row in results[2] as List<BookReadingProgressData>)
        row.bookId: row,
    };
    final comicProgress = {
      for (final row in results[3] as List<ComicReadingProgressData>)
        row.mangaId: row,
    };
    final items = <_ShelfItem>[
      for (final book in books) _ShelfItem.book(book, bookProgress[book.id]),
      for (final comic in comics)
        _ShelfItem.comic(comic, comicProgress[comic.id]),
    ]..sort((a, b) => b.activityAt.compareTo(a.activityAt));
    if (!mounted) return;
    setState(() {
      _items = items;
      _bookConfigured = results[4] as bool;
      _comicConfigured = results[5] as bool;
      _loading = false;
    });
  }

  List<_ShelfItem> get _visibleItems => switch (_filter) {
        ReadingShelfFilter.reading => _items.where((e) => e.isReading).toList(),
        ReadingShelfFilter.novels =>
          _items.where((e) => e.kind == _ShelfKind.book).toList(),
        ReadingShelfFilter.comics =>
          _items.where((e) => e.kind == _ShelfKind.comic).toList(),
        ReadingShelfFilter.all => _items,
      };

  Future<String> _primaryCharacterId() async {
    final userId = await UserStorage.getUserId();
    if (userId == null) return 'unknown';
    final chars = await CharacterService.instance.getAllCharacters(userId);
    if (chars.isEmpty) return 'unknown';
    return chars
        .firstWhere(
          (c) => c.enabled && c.isPrimaryCompanion,
          orElse: () =>
              chars.firstWhere((c) => c.enabled, orElse: () => chars.first),
        )
        .id;
  }

  Future<void> _importTxt() async {
    if (!_bookConfigured) {
      final configured = await _configureBookService();
      if (!configured) return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null || file.bytes!.isEmpty) return;
    setState(() => _busy = true);
    try {
      final book = await BookLibraryService.instance.importTxt(
        Uint8List.fromList(file.bytes!),
        file.name,
        characterId: await _primaryCharacterId(),
      );
      _toast(book == null ? '导入失败，请检查书籍服务' : '已导入「${book.title}」');
      await _load();
    } catch (e) {
      _toast('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _configureBookService() async {
    final remote = BookRemoteService(db: AppDatabase.instance);
    final controller = TextEditingController(text: await remote.getBaseUrl());
    if (!mounted) return false;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('书籍服务地址'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://你的电脑服务地址',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('保存并测试')),
        ],
      ),
    );
    if (value == null || value.isEmpty) return false;
    await remote.saveBaseUrl(value);
    final error = await remote.testConnection();
    _toast(error == null ? '书籍服务已连接' : '连接失败：$error');
    await _load();
    return error == null;
  }

  Future<void> _addComic() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加漫画链接'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
              hintText: 'https://manwa.me/book/…',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('添加')),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;
    if (!value.contains('/book/')) {
      _toast('请粘贴包含 /book/ 的漫画目录链接');
      return;
    }
    final tail = value.split('/book/').last.split(RegExp(r'[/?#]')).first;
    await ComicLibraryService.instance.addWatch(
      characterId: await _primaryCharacterId(),
      sourceSite: 'manwa.me',
      comicUrl: value,
      title: '漫画 $tail',
    );
    _toast(_comicConfigured ? '已添加，下拉刷新可同步章节' : '已在本地书架添加');
    await _load();
  }

  Future<void> _sync() async {
    if (!_comicConfigured) {
      await _load();
      return;
    }
    final count = await ComicLibraryService.instance.syncAll();
    _toast('同步完成，新增 $count 章');
    await _load();
  }

  Future<void> _open(_ShelfItem item) async {
    if (item.book case final book?) {
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                BookReaderScreen(bookId: book.id, bookTitle: book.title)),
      );
    } else if (item.comic case final comic?) {
      final progress =
          await ComicReadingProgressService.instance.getProgress(comic.id);
      ComicChapter? chapter;
      if (progress?.chapterId case final id?) {
        chapter = await ComicLibraryService.instance.getChapter(id);
      }
      chapter ??=
          await ComicLibraryService.instance.getLatestReadyChapter(comic.id);
      if (chapter == null) {
        _toast('这本还没有已就绪的章节');
        return;
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                ComicReaderScreen(mangaId: comic.id, chapterId: chapter!.id)),
      );
    }
    await _load();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleItems;
    return Scaffold(
      backgroundColor: const Color(0xFF252A22),
      body: Stack(fit: StackFit.expand, children: [
        Image.asset(_rain,
            fit: BoxFit.cover, filterQuality: FilterQuality.high),
        SafeArea(
          child: Column(children: [
            _header(),
            _filters(),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _accent))
                  : RefreshIndicator(
                      onRefresh: _sync,
                      color: _accent,
                      child: visible.isEmpty
                          ? ListView(children: [
                              const SizedBox(height: 100),
                              Center(
                                  child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 22, vertical: 18),
                                decoration: BoxDecoration(
                                    color: _fog,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: Colors.white70)),
                                child: Text(
                                    _filter == ReadingShelfFilter.reading
                                        ? '还没有正在阅读的内容'
                                        : '书架还是空的',
                                    style: const TextStyle(color: _ink)),
                              )),
                            ])
                          : _view == ReadingShelfView.list
                              ? _listView(visible)
                              : _coverView(visible),
                    ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
        child: Row(children: [
          _glassIcon(
              Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context)),
          const SizedBox(width: 12),
          const Text('阅读',
              style: TextStyle(
                  color: Color(0xFFF7F2E7),
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 5)])),
          const Spacer(),
          Text(_bookConfigured || _comicConfigured ? '已连接' : '仅本地',
              style: const TextStyle(
                  color: Color(0xE8F7F2E7),
                  fontSize: 12,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 4)])),
          const SizedBox(width: 8),
          _glassIcon(Icons.graphic_eq_rounded,
              () => context.push(AppRoutes.bookTtsVoiceLab)),
          const SizedBox(width: 6),
          _glassIcon(
              _view == ReadingShelfView.list
                  ? Icons.grid_view_rounded
                  : Icons.view_agenda_outlined,
              () => setState(() => _view = _view == ReadingShelfView.list
                  ? ReadingShelfView.covers
                  : ReadingShelfView.list)),
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            enabled: !_busy,
            onSelected: (value) => value == 'book' ? _importTxt() : _addComic(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'book',
                  child: ListTile(
                      leading: Icon(Icons.text_snippet_outlined),
                      title: Text('导入 TXT 小说'))),
              PopupMenuItem(
                  value: 'comic',
                  child: ListTile(
                      leading: Icon(Icons.auto_stories_outlined),
                      title: Text('添加漫画链接'))),
            ],
            child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: const Color(0xA8F5F1E7),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white54)),
                child: _busy
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _accent))
                    : const Icon(Icons.add_rounded, color: _ink)),
          ),
        ]),
      );

  Widget _glassIcon(IconData icon, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 19),
        style: IconButton.styleFrom(
            backgroundColor: const Color(0xA8F5F1E7), foregroundColor: _ink),
      );

  Widget _filters() {
    const labels = {
      ReadingShelfFilter.reading: '在读',
      ReadingShelfFilter.all: '全部',
      ReadingShelfFilter.novels: '小说',
      ReadingShelfFilter.comics: '漫画',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: const Color(0xA8F5F1E7),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white54)),
        child: Row(children: [
          for (final filter in ReadingShelfFilter.values)
            InkWell(
              onTap: () => setState(() => _filter = filter),
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
                decoration: BoxDecoration(
                    color: _filter == filter
                        ? const Color(0xFFE1E5D1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999)),
                child: Text(labels[filter]!,
                    style: TextStyle(
                        color: _ink,
                        fontWeight: _filter == filter
                            ? FontWeight.w700
                            : FontWeight.w500)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _listView(List<_ShelfItem> items) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 28),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          final item = items[index];
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _open(item),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                    color: _fog,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white70)),
                child: Row(children: [
                  _Cover(item: item, width: 50, height: 68),
                  const SizedBox(width: 13),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text(item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(color: _muted, fontSize: 12)),
                        const SizedBox(height: 7),
                        Text(item.progressLabel,
                            style: const TextStyle(
                                color: _accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ])),
                  const Icon(Icons.chevron_right_rounded, color: _muted),
                ]),
              ),
            ),
          );
        },
      );

  Widget _coverView(List<_ShelfItem> items) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 28),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 11,
            mainAxisSpacing: 14,
            childAspectRatio: .54),
        itemCount: items.length,
        itemBuilder: (_, index) {
          final item = items[index];
          return InkWell(
            onTap: () => _open(item),
            borderRadius: BorderRadius.circular(15),
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: _fog,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white70)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: _Cover(
                            item: item,
                            width: double.infinity,
                            height: double.infinity)),
                    const SizedBox(height: 7),
                    Text(item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            height: 1.2)),
                    const SizedBox(height: 3),
                    Text(item.progressLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 10.5)),
                  ]),
            ),
          );
        },
      );
}

enum _ShelfKind { book, comic }

class _ShelfItem {
  const _ShelfItem(
      {required this.kind,
      required this.title,
      required this.subtitle,
      required this.cover,
      required this.progressLabel,
      required this.activityAt,
      required this.isReading,
      this.book,
      this.comic});

  factory _ShelfItem.book(Book book, BookReadingProgressData? progress) =>
      _ShelfItem(
        kind: _ShelfKind.book,
        title: book.title,
        subtitle: book.author.isEmpty
            ? '小说 · ${book.chapterCount} 章'
            : '小说 · ${book.author}',
        cover: book.coverUrl,
        progressLabel: progress == null
            ? '${book.chapterCount} 章'
            : '第 ${progress.chapterNumber} 章 · ${(progress.scrollRatio * 100).round()}%',
        activityAt: progress?.readAt ?? book.updatedAt,
        isReading: progress != null,
        book: book,
      );

  factory _ShelfItem.comic(
          ComicManga comic, ComicReadingProgressData? progress) =>
      _ShelfItem(
        kind: _ShelfKind.comic,
        title: comic.title,
        subtitle: comic.sourceSite == 'demo'
            ? '漫画 · 本地样章'
            : '漫画 · ${comic.sourceSite}',
        cover: comic.coverUrl,
        progressLabel: progress == null ? '尚未开始' : '第 ${progress.page} 页',
        activityAt: progress?.readAt ?? comic.updatedAt,
        isReading: progress != null,
        comic: comic,
      );

  final _ShelfKind kind;
  final String title;
  final String subtitle;
  final String? cover;
  final String progressLabel;
  final int activityAt;
  final bool isReading;
  final Book? book;
  final ComicManga? comic;
}

class _Cover extends StatelessWidget {
  const _Cover({required this.item, required this.width, required this.height});
  final _ShelfItem item;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cover = item.cover;
    Widget image;
    if (cover == null || cover.isEmpty) {
      image = _placeholder();
    } else if (cover.startsWith('http')) {
      image = Image.network(cover,
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder());
    } else if (cover.startsWith('asset://')) {
      image = Image.asset(cover.substring(8),
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder());
    } else {
      image = Image.file(File(cover),
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder());
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(width: width, height: height, child: image),
    );
  }

  Widget _placeholder() => Container(
        color: item.kind == _ShelfKind.book
            ? const Color(0xFFADB99B)
            : const Color(0xFF9BA8A1),
        alignment: Alignment.center,
        child: Icon(
            item.kind == _ShelfKind.book
                ? Icons.menu_book_rounded
                : Icons.auto_stories_rounded,
            color: const Color(0xFFF7F4E9),
            size: 28),
      );
}
