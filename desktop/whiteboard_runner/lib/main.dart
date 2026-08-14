/// W1 whiteboard canvas lab — disposable desktop/web shell.
///
/// This entry point loads a real `WhiteboardSnapshot` fixture, opens a board
/// in the full-screen canvas, persists to a JSON file on save, and restores
/// from it on restart. It exercises the vertical slice: open → render →
/// select → drag → zoom → delete → undo/redo → save → restart-restore.
///
/// It deliberately does NOT import MemexRouter or any Memex app services.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/snapshot_integrity.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_screen.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_snapshot_store.dart';

/// Resolution for save paths (the runner runs on desktop/web).
String get _persistRoot {
  if (kIsWeb) {
    // Web: no real file system; the lab falls back to in-memory only.
    return '';
  }
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '.';
  return '$home/here-i-am-whiteboard-lab';
}

void main() {
  runApp(const WhiteboardLabApp());
}

class WhiteboardLabApp extends StatelessWidget {
  const WhiteboardLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '白板画布 Lab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF0EFEB),
      ),
      home: const LabHomePage(),
    );
  }
}

class LabHomePage extends StatefulWidget {
  const LabHomePage({super.key});

  @override
  State<LabHomePage> createState() => _LabHomePageState();
}

class _LabHomePageState extends State<LabHomePage> {
  WhiteboardSnapshot? _snapshot;
  String? _status;
  String _loadKind = 'normal';

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final result = await _loadSnapshot(_loadKind);
    setState(() {
      _snapshot = result.snapshot;
      _status = result.status;
    });
  }

  Future<_LoadOutcome> _loadSnapshot(String kind) async {
    try {
      switch (kind) {
        case 'empty':
          return _LoadOutcome(
            snapshot: kIsWeb
                ? _webFixture(kind)
                : await _loadFixture('empty_snapshot.json'),
            status: '已加载空白板 fixture',
          );
        case 'corrupt':
          if (kIsWeb) {
            return const _LoadOutcome(
              snapshot: null,
              status: '损坏快照（web 环境）：恢复失败，已进入空状态',
            );
          }
          final file = await _writeCorruptFile();
          final store = WhiteboardSnapshotStore(file.parent.path);
          final result = store.load(file.uri.pathSegments.last
              .replaceFirst('whiteboard_', '')
              .replaceAll('.json', ''));
          if (!result.isSuccess) {
            return _LoadOutcome(
              snapshot: null,
              status: '损坏快照恢复失败（预期）：${result.error}',
            );
          }
          return _LoadOutcome(
            snapshot: result.snapshot,
            status: '损坏快照已自动修复，警告：'
                '${result.integrity?.warnings.join('; ') ?? '无'}',
          );
        case 'dangling':
          if (kIsWeb) {
            return _LoadOutcome(
              snapshot: _webFixture(kind),
              status: '已加载失效引用 fixture（web 内存数据）',
            );
          }
          final raw = await _loadRawFixture('invalid_dangling_refs.json');
          final snapshot = loadSnapshot(raw);
          final integrity = validateSnapshotIntegrity(snapshot);
          return _LoadOutcome(
            snapshot: snapshot,
            status: '已加载失效引用 fixture，完整性警告：'
                '${integrity.warnings.join('; ')}',
          );
        case 'perf':
          return _LoadOutcome(
            snapshot: _generate500CardSnapshot(),
            status: '已加载 500 卡性能 fixture（内存生成）',
          );
        case 'normal':
        default:
          final snapshot = kIsWeb
              ? _webFixture('normal')
              : await _loadFixture('normal_snapshot.json');
          return _LoadOutcome(
            snapshot: snapshot,
            status: kIsWeb
                ? '已加载标准 fixture（web 内存数据）'
                : '已加载标准 fixture（normal_snapshot.json）',
          );
      }
    } catch (e) {
      return _LoadOutcome(snapshot: null, status: '加载失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0EFEB),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _status ?? '加载中…',
                style: const TextStyle(color: Color(0xFF74726C)),
              ),
            ],
          ),
        ),
      );
    }

    final persistedStore = kIsWeb ? null : WhiteboardSnapshotStore(_persistRoot);

    return Scaffold(
      backgroundColor: const Color(0xFFF0EFEB),
      body: Column(
        children: [
          // Lab toolbar — NOT part of the canvas; it is the runner harness.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Text(
                  '白板画布 Lab',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF34332F),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _loadKind,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'normal', child: Text('标准 fixture')),
                    DropdownMenuItem(value: 'empty', child: Text('空白板')),
                    DropdownMenuItem(value: 'corrupt', child: Text('损坏快照')),
                    DropdownMenuItem(value: 'dangling', child: Text('失效引用')),
                    DropdownMenuItem(value: 'perf', child: Text('500 卡')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _loadKind = v);
                      _loadInitial();
                    }
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _status ?? '',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF999790),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (persistedStore != null)
                  TextButton(
                    onPressed: () {
                      final saved = persistedStore.save(
                        snapshot.boards.isNotEmpty
                            ? snapshot.boards.first.boardId
                            : 'board_default',
                        snapshot,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            saved ? '快照已保存到磁盘' : '保存失败',
                          ),
                        ),
                      );
                    },
                    child: const Text('保存快照'),
                  ),
                if (persistedStore != null)
                  TextButton(
                    onPressed: () async {
                      final boardId = snapshot.boards.isNotEmpty
                          ? snapshot.boards.first.boardId
                          : 'board_default';
                      final result = persistedStore.load(boardId);
                      setState(() {
                        _snapshot = result.snapshot ?? snapshot;
                        _status = result.isSuccess
                            ? '已从磁盘恢复（${result.snapshot!.cards.length} 卡）'
                            : '恢复失败：${result.error}';
                      });
                    },
                    child: const Text('从磁盘恢复'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: snapshot.boards.isEmpty
                ? const Center(
                    child: Text(
                      '此 fixture 没有 board',
                      style: TextStyle(color: Color(0xFF74726C)),
                    ),
                  )
                : _buildCanvas(snapshot, persistedStore),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(
    WhiteboardSnapshot snapshot,
    WhiteboardSnapshotStore? persistedStore,
  ) {
    // Restore from disk if available.
    WhiteboardSnapshot effective = snapshot;
    if (persistedStore != null) {
      final boardId = snapshot.boards.isNotEmpty
          ? snapshot.boards.first.boardId
          : 'board_default';
      final result = persistedStore.load(boardId);
      if (result.isSuccess && result.snapshot != null) {
        effective = result.snapshot!;
      }
    }

    final boardId = effective.boards.isNotEmpty
        ? effective.boards.first.boardId
        : 'board_default';
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: effective,
      boardId: boardId,
    );

    if (persistedStore != null) {
      vm.onSaveRequested = () {
        final saved = persistedStore.save(boardId, vm.exportForSave());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(saved ? '已保存并持久化' : '保存失败')),
          );
        }
      };
    }

    return WhiteboardCanvasScreen(
      viewModel: vm,
      onExit: () {
        if (persistedStore != null) {
          persistedStore.save(boardId, vm.exportForSave());
        }
        // Reload harness (simulate restart)
        setState(() {
          _snapshot = null;
        });
        _loadInitial();
      },
    );
  }
}

class _LoadOutcome {
  final WhiteboardSnapshot? snapshot;
  final String status;
  const _LoadOutcome({this.snapshot, required this.status});
}

/// Builds an in-memory snapshot for web mode (no disk access).
WhiteboardSnapshot _webFixture(String kind) {
  final now = DateTime(2026, 8, 15);
  switch (kind) {
    case 'empty':
      return WhiteboardSnapshot(
        boards: [
          Board(boardId: 'board_empty', name: '空白板', createdAt: now),
        ],
      );
    case 'dangling':
      return WhiteboardSnapshot(
        boards: [
          Board(boardId: 'board_dangling', name: '失效引用演示', createdAt: now),
        ],
        cards: [
          CardContract(
            cardId: 'card_ok',
            cardKind: CardKind.note,
            title: '正常卡',
            body: '这张卡有正常引用。',
            createdAt: now,
          ),
        ],
        boardItems: const [
          BoardItem(itemId: 'item_ok', boardId: 'board_dangling', cardId: 'card_ok'),
          BoardItem(itemId: 'item_missing', boardId: 'board_dangling', cardId: 'card_nonexistent'),
        ],
      );
    case 'normal':
    default:
      return WhiteboardSnapshot(
        boards: [
          Board(
            boardId: 'board_mvp',
            name: '白板 MVP 结构',
            createdAt: now,
          ),
          Board(
            boardId: 'board_stage',
            name: '舞台灯光与配色',
            createdAt: now,
          ),
        ],
        cards: [
          CardContract(
            cardId: 'card_spine',
            cardKind: CardKind.note,
            title: '统一卡片脊柱',
            body: '统一 Card 身份不意味着统一缩略条。白板只保存摆放，不复制内容。',
            tags: const ['文字', '架构'],
            createdAt: now,
          ),
          CardContract(
            cardId: 'card_affine',
            cardKind: CardKind.source,
            title: 'AFFiNE 白板架构分析',
            body: 'BlockSuite、Edgeless 与自有数据快照之间的适配边界。',
            tags: const ['网页', '白板'],
            createdAt: now,
          ),
          CardContract(
            cardId: 'card_book',
            cardKind: CardKind.source,
            title: '置身事内',
            body: '第四章 · 阅读进度 62%',
            tags: const ['书籍', '经济'],
            createdAt: now,
          ),
          CardContract(
            cardId: 'card_plave',
            cardKind: CardKind.source,
            title: 'PLAVE 舞台灯光研究',
            body: '02:22 后灯光由冷色切换到暖白。',
            tags: const ['视频', '舞台'],
            createdAt: now,
          ),
          CardContract(
            cardId: 'card_annotation',
            cardKind: CardKind.annotation,
            title: '土地财政的结构',
            body: '土地出让金不仅是收入项目，也影响城市扩张和公共服务节奏。',
            tags: const ['批注', '财政'],
            createdAt: now,
          ),
        ],
        boardItems: [
          BoardItem(
            itemId: 'item_spine',
            boardId: 'board_mvp',
            cardId: 'card_spine',
            x: 120,
            y: 90,
            width: 280,
            height: 200,
            zIndex: 1,
          ),
          BoardItem(
            itemId: 'item_affine',
            boardId: 'board_mvp',
            cardId: 'card_affine',
            x: 470,
            y: 150,
            width: 260,
            height: 220,
            zIndex: 2,
          ),
          BoardItem(
            itemId: 'item_book',
            boardId: 'board_mvp',
            cardId: 'card_book',
            x: 120,
            y: 330,
            width: 240,
            height: 180,
            zIndex: 3,
          ),
          BoardItem(
            itemId: 'item_plave',
            boardId: 'board_stage',
            cardId: 'card_plave',
            x: 110,
            y: 90,
            width: 320,
            height: 250,
            zIndex: 1,
          ),
        ],
      );
  }
}

Future<WhiteboardSnapshot> _loadFixture(String filename) async {
  final raw = await _loadRawFixture(filename);
  return loadSnapshot(raw);
}

Future<Map<String, dynamic>> _loadRawFixture(String filename) async {
  if (kIsWeb) {
    throw UnsupportedError('Web runner cannot read fixture files from disk. '
        'Run on Windows desktop instead.');
  }
  final path = 'test/domain/whiteboard/fixtures/$filename';
  final file = File(path);
  if (!file.existsSync()) {
    throw FileSystemException('Fixture not found', path);
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Future<File> _writeCorruptFile() async {
  final dir = Directory('${_persistRoot}_corrupt');
  dir.createSync(recursive: true);
  final file = File('${dir.path}/whiteboard_corrupt_board.json');
  file.writeAsStringSync('{ "invalid json,,, }');
  return file;
}

/// Generates a 500-card performance fixture in memory.
WhiteboardSnapshot _generate500CardSnapshot() {
  final now = DateTime(2026, 8, 15);
  final cards = <dynamic>[];
  final items = <dynamic>[];
  for (int i = 0; i < 500; i++) {
    final row = i ~/ 20;
    final col = i % 20;
    cards.add({
      'card_id': 'perf_card_$i',
      'card_kind': i % 5 == 0 ? 'source' : 'note',
      'title': '性能卡 $i',
      'body': '500 卡性能测试第 $i 张卡片的正文内容。',
      'tags': ['性能', '卡_$i'],
      'created_by': 'user',
      'created_at': now.toUtc().toIso8601String(),
    });
    items.add({
      'item_id': 'perf_item_$i',
      'board_id': 'board_perf',
      'card_id': 'perf_card_$i',
      'x': 100.0 + col * 150,
      'y': 100.0 + row * 130,
      'width': 140.0,
      'height': 110.0,
      'z_index': i,
    });
  }
  return WhiteboardSnapshot(
    cards: cards
        .map((c) => CardContract.fromJson(c as Map<String, dynamic>))
        .toList(),
    boards: [
      Board.fromJson({
        'board_id': 'board_perf',
        'name': '性能测试 500 卡',
        'created_by': 'user',
        'created_at': now.toUtc().toIso8601String(),
      }),
    ],
    boardItems: items
        .map((i) => BoardItem.fromJson(i as Map<String, dynamic>))
        .toList(),
  );
}