import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/data/services/comic/comic_library_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/book/book_reader_screen.dart';
import 'package:memex/ui/comic/comic_reader_screen.dart';
import 'package:memex/ui/game/widgets/game_library_screen.dart';
import 'package:memex/ui/reading/widgets/unified_reading_screen.dart';

class InterestHubScreen extends StatefulWidget {
  const InterestHubScreen({super.key});

  @override
  State<InterestHubScreen> createState() => _InterestHubScreenState();
}

class _InterestHubScreenState extends State<InterestHubScreen> {
  static const _rain = 'assets/images/雨玻璃.jpg';
  static const _ink = Color(0xFF293025);
  static const _muted = Color(0xFF667061);
  static const _fog = Color(0xEAF7F5ED);

  List<_RecentInterest> _recent = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDatabase.instance;
    final results = await Future.wait([
      (db.select(db.books)
            ..where((t) => t.status.equals('active'))
            ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)]))
          .get(),
      (db.select(db.bookReadingProgress)
            ..orderBy([(t) => drift.OrderingTerm.desc(t.readAt)])
            ..limit(2))
          .get(),
      (db.select(db.comicMangas)
            ..where((t) => t.status.isNotIn(['removed']))
            ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)]))
          .get(),
      (db.select(db.comicReadingProgress)
            ..orderBy([(t) => drift.OrderingTerm.desc(t.readAt)])
            ..limit(2))
          .get(),
      (db.select(db.gameSessions)
            ..where((t) => t.status.isNotIn(['archived']))
            ..orderBy([(t) => drift.OrderingTerm.desc(t.lastPlayedAt)])
            ..limit(2))
          .get(),
    ]);
    final books = {
      for (final item in results[0] as List<Book>) item.id: item,
    };
    final comics = {
      for (final item in results[2] as List<ComicManga>) item.id: item,
    };
    final recent = <_RecentInterest>[
      for (final progress in results[1] as List<BookReadingProgressData>)
        if (books[progress.bookId] case final book?)
          _RecentInterest.book(book, progress),
      for (final progress in results[3] as List<ComicReadingProgressData>)
        if (comics[progress.mangaId] case final comic?)
          _RecentInterest.comic(comic, progress),
      for (final item in results[4] as List<GameSession>)
        _RecentInterest.game(item),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (mounted) setState(() => _recent = recent.take(4).toList());
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    await _load();
  }

  Future<void> _openRecent(_RecentInterest item) async {
    switch (item.kind) {
      case _RecentInterestKind.book:
        await _open(BookReaderScreen(
          bookId: item.id,
          bookTitle: item.title,
        ));
      case _RecentInterestKind.comic:
        var chapterId = item.chapterId;
        if (chapterId != null) {
          final chapter =
              await ComicLibraryService.instance.getChapter(chapterId);
          if (chapter == null || chapter.status != 'ready') chapterId = null;
        }
        chapterId ??=
            (await ComicLibraryService.instance.getLatestReadyChapter(item.id))
                ?.id;
        if (chapterId == null) {
          _toast('这本还没有已就绪的章节');
          return;
        }
        if (!mounted) return;
        await _open(ComicReaderScreen(
          mangaId: item.id,
          chapterId: chapterId,
        ));
      case _RecentInterestKind.game:
        GameDefinition? definition;
        if (item.definitionId case final definitionId?) {
          definition = await (AppDatabase.instance
                  .select(AppDatabase.instance.gameDefinitions)
                ..where((t) => t.id.equals(definitionId)))
              .getSingleOrNull();
        }
        if (!mounted) return;
        await _open(GamePlayScreen(
          sessionId: item.id,
          definition: definition,
        ));
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF252A22),
      body: Stack(fit: StackFit.expand, children: [
        Image.asset(_rain, fit: BoxFit.cover),
        SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 7, 14, 30),
            children: [
              Row(children: [
                IconButton(
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/');
                    }
                  },
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  style: IconButton.styleFrom(
                      backgroundColor: const Color(0xA8F5F1E7),
                      foregroundColor: _ink),
                ),
                const SizedBox(width: 12),
                const Text('兴趣',
                    style: TextStyle(
                        color: Color(0xFFF7F2E7),
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        shadows: [
                          Shadow(color: Colors.black45, blurRadius: 5)
                        ])),
              ]),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                    child: _entry(
                  icon: Icons.menu_book_rounded,
                  title: '阅读',
                  subtitle: '小说与漫画书架',
                  onTap: () => _open(const UnifiedReadingScreen()),
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: _entry(
                  icon: Icons.sports_esports_rounded,
                  title: '游戏',
                  subtitle: '角色卡与独立故事',
                  onTap: () => _open(const GameLibraryScreen()),
                )),
              ]),
              const SizedBox(height: 26),
              const Text('最近活动',
                  style: TextStyle(
                      color: Color(0xFFF7F2E7),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 4)])),
              const SizedBox(height: 10),
              if (_recent.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: _decoration(),
                  child: const Text('读一本书，或开始一段故事后，最近活动会出现在这里。',
                      style: TextStyle(color: _muted, height: 1.45)),
                )
              else
                for (final item in _recent)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _openRecent(item),
                        borderRadius: BorderRadius.circular(16),
                        child: Ink(
                          padding: const EdgeInsets.all(13),
                          decoration: _decoration(),
                          child: Row(children: [
                            Container(
                                width: 38,
                                height: 38,
                                decoration: const BoxDecoration(
                                    color: Color(0xFFDDE2CD),
                                    shape: BoxShape.circle),
                                child: Icon(item.icon,
                                    color: const Color(0xFF737B46), size: 19)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: _ink,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 3),
                                  Text(
                                      '${item.type} · ${item.progressLabel} · ${_date(item.timestamp)}',
                                      style: const TextStyle(
                                          color: _muted, fontSize: 11)),
                                ])),
                            const Icon(Icons.arrow_forward_ios_rounded,
                                color: Color(0xFF737B46), size: 14),
                          ]),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _entry(
          {required IconData icon,
          required String title,
          required String subtitle,
          required VoidCallback onTap}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 180,
          padding: const EdgeInsets.all(16),
          decoration: _decoration(radius: 20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                    color: Color(0xFFDDE2CD), shape: BoxShape.circle),
                child: Icon(icon, color: const Color(0xFF737B46), size: 24)),
            const Spacer(),
            Text(title,
                style: const TextStyle(
                    color: _ink, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 8),
            const Align(
                alignment: Alignment.centerRight,
                child: Icon(Icons.arrow_forward_rounded,
                    color: Color(0xFF737B46), size: 19)),
          ]),
        ),
      );

  BoxDecoration _decoration({double radius = 16}) => BoxDecoration(
        color: _fog,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white70),
        boxShadow: const [
          BoxShadow(
              color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 5))
        ],
      );

  String _date(int seconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return '${dt.month}月${dt.day}日';
  }
}

enum _RecentInterestKind { book, comic, game }

class _RecentInterest {
  const _RecentInterest({
    required this.kind,
    required this.id,
    required this.type,
    required this.title,
    required this.progressLabel,
    required this.timestamp,
    required this.icon,
    this.chapterId,
    this.definitionId,
  });

  factory _RecentInterest.book(Book book, BookReadingProgressData progress) =>
      _RecentInterest(
        kind: _RecentInterestKind.book,
        id: book.id,
        type: '小说',
        title: book.title,
        progressLabel:
            '第 ${progress.chapterNumber} 章 · ${(progress.scrollRatio * 100).round()}%',
        timestamp: progress.readAt,
        icon: Icons.menu_book_rounded,
      );

  factory _RecentInterest.comic(
          ComicManga comic, ComicReadingProgressData progress) =>
      _RecentInterest(
        kind: _RecentInterestKind.comic,
        id: comic.id,
        type: '漫画',
        title: comic.title,
        progressLabel: '第 ${progress.page} 页',
        timestamp: progress.readAt,
        icon: Icons.auto_stories_rounded,
        chapterId: progress.chapterId,
      );

  factory _RecentInterest.game(GameSession session) => _RecentInterest(
        kind: _RecentInterestKind.game,
        id: session.id,
        type: session.gameType == 'turtle_soup' ? '海龟汤' : '游戏',
        title: session.sessionTitle,
        progressLabel: session.gameType == 'turtle_soup'
            ? session.status == 'ended'
                ? '已揭晓'
                : '继续猜这碗汤'
            : session.status == 'ended'
                ? '已结束'
                : '继续上次剧情',
        timestamp: session.lastPlayedAt,
        icon: session.gameType == 'turtle_soup'
            ? Icons.psychology_alt_rounded
            : Icons.sports_esports_rounded,
        definitionId: session.definitionId,
      );

  final _RecentInterestKind kind;
  final String id;
  final String type;
  final String title;
  final String progressLabel;
  final int timestamp;
  final IconData icon;
  final String? chapterId;
  final String? definitionId;
}
