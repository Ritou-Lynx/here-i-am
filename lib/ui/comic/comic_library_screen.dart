import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:memex/data/memory_v3/models/topic_thread_intent.dart';
import 'package:memex/data/memory_v3/services/topic_thread_service.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/comic/comic_library_service.dart';
import 'package:memex/data/services/comic/comic_reading_progress_service.dart';
import 'package:memex/data/services/comic/comic_remote_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/comic/comic_reader_screen.dart';
import 'package:memex/utils/user_storage.dart';

/// Minimal manga "bookshelf". This is the entry screen for co-reading.
///
/// Local-first: on first launch with an empty library it seeds a bundled
/// sample chapter so reading + zoom + chat can be tried with zero setup.
/// Online enhancement: when a Hermes comic-server URL is configured, "add
/// watch" registers a real manwa book and pull-to-refresh syncs its crawled
/// chapters. Without the server, the shelf still works for the demo.
class ComicLibraryScreen extends StatefulWidget {
  const ComicLibraryScreen({super.key});

  @override
  State<ComicLibraryScreen> createState() => _ComicLibraryScreenState();
}

class _ComicLibraryScreenState extends State<ComicLibraryScreen> {
  static const _demoMangaId = 'demo_manga_1';
  static const _demoChapterId = 'demo_chapter_1';
  static const _demoSeededKey = 'comic_demo_seeded_v1';

  List<ComicManga> _library = const [];
  bool _loading = true;
  bool _configured = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(seedIfEmpty: true);
  }

  Future<void> _load({bool seedIfEmpty = false}) async {
    try {
      final remote = ComicRemoteService(db: AppDatabase.instance);
      final configured = await remote.isConfigured();
      var library = await ComicLibraryService.instance.getLibrary();

      if (library.isEmpty && seedIfEmpty) {
        final seeded = await _kvGet(_demoSeededKey);
        if (seeded == null) {
          await _seedDemo();
          await _kvSet(_demoSeededKey, '1');
          library = await ComicLibraryService.instance.getLibrary();
        }
      }

      if (!mounted) return;
      setState(() {
        _library = library;
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

  Future<String?> _kvGet(String key) async {
    final row = await (AppDatabase.instance.select(AppDatabase.instance.kvStore)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _kvSet(String key, String value) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await AppDatabase.instance
        .into(AppDatabase.instance.kvStore)
        .insertOnConflictUpdate(
          KvStoreCompanion.insert(key: key, value: Value(value), updatedAt: Value(now)),
        );
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

  Future<void> _seedDemo() async {
    final db = AppDatabase.instance;
    final charId = await _primaryCharacterId();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await db.into(db.comicMangas).insertOnConflictUpdate(
          ComicMangasCompanion.insert(
            id: _demoMangaId,
            characterId: charId.isEmpty ? 'demo' : charId,
            sourceSite: 'demo',
            comicUrl: 'demo://local',
            title: '样章 · 不要养brat',
            status: const Value('active'),
            createdAt: now,
            updatedAt: now,
          ),
        );

    final pages = List.generate(
      6,
      (i) => {
        'page_num': i + 1,
        'src': 'asset://assets/comic_scaffold/${(i + 1).toString().padLeft(3, '0')}.png',
      },
    );
    await db.into(db.comicChapters).insertOnConflictUpdate(
          ComicChaptersCompanion.insert(
            id: _demoChapterId,
            mangaId: _demoMangaId,
            chapterNumber: 1,
            chapterTitle: const Value('第01话 (样章)'),
            chapterUrl: 'demo://local/chapter/1',
            pageCount: const Value(6),
            pagesJson: Value(jsonEncode(pages)),
            status: const Value('ready'),
            createdAt: now,
            updatedAt: now,
          ),
        );

    final raw = await rootBundle.loadString('assets/comic_scaffold/screenplay.json');
    final List<dynamic> sp = jsonDecode(raw);
    for (final p in sp) {
      final n = (p['page_num'] as num?)?.toInt() ?? 0;
      if (n <= 0) continue;
      await db.into(db.comicPageScreenplays).insertOnConflictUpdate(
            ComicPageScreenplaysCompanion(
              id: Value('demo_sp_$n'),
              chapterId: Value(_demoChapterId),
              pageNum: Value(n),
              screenplayJson: Value(jsonEncode(p)),
              createdAt: Value(now),
            ),
          );
    }

    await ComicReadingProgressService.instance.recordProgress(
      mangaId: _demoMangaId,
      chapterId: _demoChapterId,
      page: 1,
    );
  }

  Future<void> _setMangaIntents(BuildContext context, ComicManga manga) async {
    final svc = TopicThreadService(db: AppDatabase.instance);
    final threads = await svc.getThreads();
    final current = TopicThreadIntentItem.parseList(manga.intentsJson)
        .map((e) => e.threadId)
        .toList();

    if (!context.mounted) return;
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MangaIntentPickerSheet(
        mangaId: manga.id,
        mangaTitle: manga.title,
        allThreads: threads,
        selectedIds: current,
      ),
    );
    if (selected == null) return;
    final items = threads
        .where((t) => selected.contains(t.id))
        .map((t) => TopicThreadIntentItem(threadId: t.id, threadTitle: t.title))
        .toList();
    final json = TopicThreadIntentItem.encodeList(items);
    await (AppDatabase.instance.update(AppDatabase.instance.comicMangas)
          ..where((m) => m.id.equals(manga.id)))
        .write(ComicMangasCompanion(intentsJson: Value(json)));
    _load();
  }

  Future<void> _openManga(ComicManga m) async {
    final progress = await ComicReadingProgressService.instance.getProgress(m.id);
    ComicChapter? chapter;
    if (progress != null && progress.chapterId != null) {
      chapter = await ComicLibraryService.instance.getChapter(progress.chapterId!);
    }
    chapter ??= await ComicLibraryService.instance.getLatestReadyChapter(m.id);
    if (chapter == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这本还没有已就绪的章节。配置电脑服务并等待爬取后再来。')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ComicReaderScreen(mangaId: m.id, chapterId: chapter!.id),
      ),
    );
  }

  Future<void> _addWatch() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加关注的漫画'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://manwa.me/book/xxxxxx',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    if (!url.contains('/book/')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请粘贴漫画目录页链接（含 /book/）')),
      );
      return;
    }
    final charId = await _primaryCharacterId();
    final tail = url.split('/book/').last.split(RegExp(r'[/?#]')).first;
    await ComicLibraryService.instance.addWatch(
      characterId: charId.isEmpty ? 'unknown' : charId,
      sourceSite: 'manwa.me',
      comicUrl: url,
      title: '漫画 $tail',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_configured
            ? '已登记，并通知电脑服务。下拉刷新可拉取已爬章节。'
            : '已本地登记。要让这本被自动爬取，请先在右上配置电脑服务地址。'),
      ),
    );
    _load();
  }

  Future<void> _configureServer() async {
    final remote = ComicRemoteService(db: AppDatabase.instance);
    final cur = await remote.getConfig();
    final ctrl = TextEditingController(text: cur.baseUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('漫画电脑服务地址'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('填 Tailscale HTTPS 地址，例如 https://xxx.ts.net:8443。'
                '留空则只用本地样章。'),
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
    await remote.saveConfig(baseUrl: url);
    final err = await remote.testConnection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(url.isEmpty
            ? '已清空，回到本地样章模式。'
            : (err == null ? '连接成功 ✓' : '连接失败：$err')),
      ),
    );
    _load();
  }

  Future<void> _sync() async {
    if (!_configured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未配置电脑服务，无法同步。右上配置地址后再下拉。')),
      );
      return;
    }
    final n = await ComicLibraryService.instance.syncAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('同步完成，新增 $n 章')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('漫画书架'),
        actions: [
          IconButton(
            icon: Icon(_configured ? Icons.cloud_done : Icons.cloud_off),
            tooltip: '电脑服务地址',
            onPressed: _configureServer,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addWatch,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _sync,
                  child: _library.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 80),
                            Center(child: Text('还没有漫画。点右下角 + 添加关注。')),
                          ],
                        )
                      : ListView.builder(
                          itemCount: _library.length,
                          itemBuilder: (_, i) {
                            final m = _library[i];
                            final isDemo = m.sourceSite == 'demo';
                            return ListTile(
                              leading: const Icon(Icons.menu_book),
                              title: Text(m.title),
                              subtitle: Text(isDemo
                                  ? '本地样章 · 可直接读'
                                  : '${m.sourceSite} · 下拉同步更新'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.topic_outlined, size: 20),
                                    tooltip: '设置话题关联',
                                    onPressed: () => _setMangaIntents(context, m),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20),
                                    tooltip: '删除',
                                    onPressed: () async {
                                      final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('删除漫画'),
                                          content: Text('确定要删除「${m.title}」吗？'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
                                          ],
                                        ),
                                      );
                                      if (ok == true) {
                                        await ComicLibraryService.instance.removeWatch(m.id);
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('已删除')),
                                        );
                                        _load();
                                      }
                                    },
                                  ),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: () => _openManga(m),
                            );
                          },
                        ),
                ),
    );
  }
}

class _MangaIntentPickerSheet extends StatefulWidget {
  final String mangaId;
  final String mangaTitle;
  final List<TopicThread> allThreads;
  final List<String> selectedIds;

  const _MangaIntentPickerSheet({
    required this.mangaId,
    required this.mangaTitle,
    required this.allThreads,
    required this.selectedIds,
  });

  @override
  State<_MangaIntentPickerSheet> createState() => _MangaIntentPickerSheetState();
}

class _MangaIntentPickerSheetState extends State<_MangaIntentPickerSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('设置话题追踪',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          if (widget.allThreads.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('还没有话题线索。先去生活空间 → 话题线索创建一个吧。'),
            )
          else
            ...widget.allThreads.map((t) => CheckboxListTile(
                  title: Text(t.title),
                  subtitle: t.currentStage.isNotEmpty
                      ? Text(t.currentStage,
                          maxLines: 1, overflow: TextOverflow.ellipsis)
                      : null,
                  value: _selected.contains(t.id),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(t.id);
                    } else {
                      _selected.remove(t.id);
                    }
                  }),
                )),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消')),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('保存')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}