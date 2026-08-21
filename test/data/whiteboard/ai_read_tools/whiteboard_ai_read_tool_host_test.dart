import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/ai_read_tools/whiteboard_ai_read_models.dart';
import 'package:memex/data/whiteboard/ai_read_tools/whiteboard_ai_read_tool_host.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late UnifiedCardRepository repository;
  late WhiteboardDriftStore store;
  late WhiteboardAiReadToolHost host;
  late _Fixture fixture;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('w5_read_tool_host_');
    db = AppDatabase.forTesting(
      NativeDatabase(File('${tempDir.path}/whiteboard.sqlite')),
    );
    repository = UnifiedCardRepository(db: db, whiteboardRoot: tempDir);
    store = WhiteboardDriftStore(db);
    host = WhiteboardAiReadToolHost(cards: repository, boards: store);
    fixture = await _seed(repository, store);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('returns bounded Card + Source + Board relationships as JSON', () async {
    final result = await host.readSelection(
      WhiteboardAiReadRequest(
        boardId: fixture.boardId,
        cardIds: [fixture.noteCardId, fixture.sourceCardId],
        sourceIds: [fixture.sourceId],
      ),
    );

    expect(result.status, WhiteboardAiReadStatus.ok);
    expect(result.board?.boardId, fixture.boardId);
    expect(result.cards.map((card) => card.cardId), [
      fixture.noteCardId,
      fixture.sourceCardId,
    ]);
    expect(result.cards.first.body, contains('[local_path_redacted]'));
    expect(result.sources.single.sourceId, fixture.sourceId);
    expect(result.sources.single.versions, hasLength(1));
    expect(
      result.boardItems,
      hasLength(3),
      reason: 'one Card may have multiple stable BoardItem occurrences',
    );
    expect(result.groups.map((group) => group.groupId), ['group_research']);
    expect(result.groupMembers, hasLength(2));
    expect(result.edges.map((edge) => edge.edgeId), ['edge_related']);

    final encoded = jsonEncode(result.toJson());
    expect(encoded, contains('unified read body'));
    expect(encoded, isNot(contains('source_metadata_secret')));
    expect(encoded, isNot(contains('presentation_secret')));
    expect(encoded, isNot(contains('view_state_secret')));
    expect(encoded, isNot(contains('group_style_secret')));
    expect(encoded, isNot(contains('edge_style_secret')));
    expect(encoded, isNot(contains('object_ref')));
    expect(encoded, isNot(contains(tempDir.path)));
    expect(encoded, isNot(contains(r'C:/Users/USER')));

    final json = result.toJson();
    final firstCardJson = (json['cards'] as List).first as Map<String, dynamic>;
    expect(firstCardJson, contains('body_excerpt'));
    expect(firstCardJson, isNot(contains('summary')));
    final sourceJson = (json['sources'] as List).single as Map<String, dynamic>;
    expect(sourceJson['untrusted_metadata_omitted'], isTrue);
    expect(sourceJson, isNot(contains('metadata')));
    expect(
      ((json['cards'] as List).first as Map<String, dynamic>)['provenance'],
      containsPair('entity_id', fixture.noteCardId),
    );
  });

  test(
    'missing and soft-deleted entities are omitted with stable issues',
    () async {
      final result = await host.readSelection(
        WhiteboardAiReadRequest(
          boardId: fixture.boardId,
          cardIds: [fixture.deletedCardId, 'card_missing'],
          sourceIds: [fixture.deletedSourceId, 'source_missing'],
        ),
      );

      expect(result.status, WhiteboardAiReadStatus.partial);
      expect(result.cards, isEmpty);
      expect(result.sources, isEmpty);
      expect(
        result.boardItems,
        isEmpty,
        reason: 'placements of unavailable Cards must not leak',
      );
      expect(
        result.issues.map((issue) => issue.code),
        containsAll(['card_absent_or_deleted', 'source_absent_or_deleted']),
      );
      expect(
        jsonEncode(result.toJson()),
        isNot(contains('deleted source body')),
      );
    },
  );

  test(
    'deleted or absent board fails closed without raw store errors',
    () async {
      expect(await store.delete(fixture.boardId), isTrue);

      final result = await host.readSelection(
        WhiteboardAiReadRequest(
          boardId: fixture.boardId,
          cardIds: [fixture.noteCardId],
          sourceIds: const [],
        ),
      );

      expect(result.status, WhiteboardAiReadStatus.unavailable);
      expect(result.board, isNull);
      expect(result.cards, isEmpty);
      final encoded = jsonEncode(result.toJson());
      expect(encoded, contains('board_absent_deleted_or_unavailable'));
      expect(encoded, isNot(contains('Failed to load snapshot')));
      expect(encoded, isNot(contains('sqlite')));
    },
  );

  test(
    'request quantity and unsafe ids are rejected before any projection',
    () async {
      final strictHost = WhiteboardAiReadToolHost(
        cards: repository,
        boards: store,
        limits: WhiteboardAiReadLimits(maxCardIds: 1),
      );

      final tooMany = await strictHost.readSelection(
        WhiteboardAiReadRequest(
          boardId: fixture.boardId,
          cardIds: [fixture.noteCardId, fixture.sourceCardId],
          sourceIds: const [],
        ),
      );
      expect(tooMany.status, WhiteboardAiReadStatus.invalidRequest);
      expect(tooMany.cards, isEmpty);
      expect(tooMany.issues.single.code, 'card_id_limit_exceeded');
      expect(tooMany.request.cardIds, hasLength(1));

      const localPath = r'C:/Users/USER';
      final unsafe = await host.readSelection(
        const WhiteboardAiReadRequest(
          boardId: localPath,
          cardIds: [localPath],
          sourceIds: [],
        ),
      );
      expect(unsafe.status, WhiteboardAiReadStatus.invalidRequest);
      expect(jsonEncode(unsafe.toJson()), isNot(contains(localPath)));
    },
  );

  test('relation and body limits truncate deterministically', () async {
    final strictHost = WhiteboardAiReadToolHost(
      cards: repository,
      boards: store,
      limits: WhiteboardAiReadLimits(maxBoardItems: 1, maxBodyRunes: 12),
    );

    final result = await strictHost.readSelection(
      WhiteboardAiReadRequest(
        boardId: fixture.boardId,
        cardIds: [fixture.noteCardId],
        sourceIds: const [],
      ),
    );

    expect(result.status, WhiteboardAiReadStatus.partial);
    expect(result.boardItems, hasLength(1));
    expect(result.cards.single.body.runes.length, 12);
    expect(result.cards.single.bodyTruncated, isTrue);
    expect(
      result.truncations.map((item) => item.field),
      containsAll(['board_items', 'cards.${fixture.noteCardId}.body']),
    );
  });

  test('limit configuration cannot expand non-overridable ceilings', () {
    expect(
      () => WhiteboardAiReadLimits(
        maxCardIds: WhiteboardAiReadLimits.hardMaxCardIds + 1,
      ),
      throwsRangeError,
    );
    expect(
      () => WhiteboardAiReadLimits(
        maxBodyRunes: WhiteboardAiReadLimits.hardMaxBodyRunes + 1,
      ),
      throwsRangeError,
    );
    expect(
      () => WhiteboardAiReadLimits(
        maxEdges: WhiteboardAiReadLimits.hardMaxEdges + 1,
      ),
      throwsRangeError,
    );
    expect(
      () => WhiteboardAiReadLimits(maxCardIds: -1),
      throwsRangeError,
    );
    expect(
      () => WhiteboardAiReadLimits(
        maxSerializedUtf8Bytes:
            WhiteboardAiReadLimits.hardMaxSerializedUtf8Bytes + 1,
      ),
      throwsRangeError,
    );
  });

  test(
    'global UTF-8 budget truncates multi-card Unicode output honestly',
    () async {
      const cardCount = 12;
      final unicodeBody = List.filled(12000, '界🙂').join();
      final loaded = await store.load(fixture.boardId);
      expect(loaded.isSuccess, isTrue);
      final extraItems = <BoardItem>[];
      final cardIds = <String>[];
      for (var index = 0; index < cardCount; index++) {
        final cardId = 'card_unicode_$index';
        cardIds.add(cardId);
        await repository.createTextCard(
          cardId: cardId,
          title: 'Unicode $index',
          body: unicodeBody,
          createdAt: DateTime.utc(2026, 8, 21, 9, index),
        );
        extraItems.add(
          BoardItem(
            itemId: 'item_unicode_$index',
            boardId: fixture.boardId,
            cardId: cardId,
            x: index * 20,
          ),
        );
      }
      final current = loaded.snapshot!;
      expect(
        await store.save(
          fixture.boardId,
          WhiteboardSnapshot(
            boards: current.boards,
            boardItems: [...current.boardItems, ...extraItems],
            groups: current.groups,
            groupMembers: current.groupMembers,
            edges: current.edges,
            viewport: current.viewport,
            updatedAt: current.updatedAt,
          ),
        ),
        isTrue,
      );
      const budget = WhiteboardAiReadLimits.minSerializedUtf8Bytes;
      final budgetedHost = WhiteboardAiReadToolHost(
        cards: repository,
        boards: store,
        limits: WhiteboardAiReadLimits(
          maxCardIds: cardCount,
          maxBodyRunes: WhiteboardAiReadLimits.hardMaxBodyRunes,
          maxSerializedUtf8Bytes: budget,
        ),
      );

      final result = await budgetedHost.readSelection(
        WhiteboardAiReadRequest(
          boardId: fixture.boardId,
          cardIds: cardIds,
          sourceIds: const [],
        ),
      );
      final encoded = jsonEncode(result.toJson());

      expect(utf8.encode(encoded).length, lessThanOrEqualTo(budget));
      expect(result.status, WhiteboardAiReadStatus.partial);
      expect(
        result.truncations,
        contains(
          isA<WhiteboardAiReadTruncation>()
              .having(
                (item) => item.field,
                'field',
                'serialized_output_utf8_bytes',
              )
              .having((item) => item.limit, 'limit', budget)
              .having(
                (item) => item.omittedCount,
                'omittedCount',
                greaterThan(0),
              ),
        ),
      );
      expect(encoded, contains('body_excerpt'));
      expect(encoded, isNot(contains('summary')));
    },
  );

  test(
    'all text exits redact complete local paths including spaces',
    () async {
      await repository.updateCardMetadata(
        fixture.noteCardId,
        title: r'win C:/Users/USER Private\title.txt title_tail',
        body: [
          r'win C:/Users/USER Private\body.txt win_tail',
          r'unc \\server\Team Share\secret.txt unc_tail',
          'unix /home/USER/My Private/body.txt unix_tail',
          'uri file:///C:/Users/USER/My%20Private/body.txt uri_tail',
        ].join('\n'),
        tags: const ['tag /Users/USER/My Private/tag.txt tag_tail'],
      );
      final loaded = await store.load(fixture.boardId);
      final current = loaded.snapshot!;
      final activeSource = await repository.getSource(fixture.sourceId);
      expect(activeSource, isNotNull);
      final sourceWithPath = SourceContent(
        sourceId: activeSource!.sourceId,
        mediaType: activeSource.mediaType,
        title: r'source C:/Users/USER Private\source.html source_tail',
        ownerSpace: activeSource.ownerSpace,
        origin: activeSource.origin,
        provider: activeSource.provider,
        canonicalId: 'file:///home/USER/My Private/source.html canonical_tail',
        mimeType: activeSource.mimeType,
        currentVersionId: activeSource.currentVersionId,
        contentHash: activeSource.contentHash,
        objectRef: activeSource.objectRef,
        metadata: activeSource.metadata,
        createdAt: activeSource.createdAt,
        updatedAt: activeSource.updatedAt,
      );
      final groups = [
        for (final group in current.groups)
          BoardGroup(
            groupId: group.groupId,
            boardId: group.boardId,
            name: '/Users/USER/My Private/group group_tail',
            collapsed: group.collapsed,
          ),
      ];
      final edges = [
        for (final edge in current.edges)
          BoardEdge(
            edgeId: edge.edgeId,
            boardId: edge.boardId,
            fromItemId: edge.fromItemId,
            toItemId: edge.toItemId,
            direction: edge.direction,
            semanticType: edge.semanticType,
            label: r'edge \\server\Team Share\edge.txt edge_tail',
            createdBy: edge.createdBy,
            createdAt: edge.createdAt,
            deletedAt: edge.deletedAt,
          ),
      ];
      expect(
        await store.save(
          fixture.boardId,
          WhiteboardSnapshot(
            boards: current.boards,
            sources: [sourceWithPath],
            boardItems: current.boardItems,
            groups: groups,
            groupMembers: current.groupMembers,
            edges: edges,
            viewport: current.viewport,
            updatedAt: current.updatedAt,
          ),
        ),
        isTrue,
      );

      final result = await host.readSelection(
        WhiteboardAiReadRequest(
          boardId: fixture.boardId,
          cardIds: [fixture.noteCardId, fixture.sourceCardId],
          sourceIds: [fixture.sourceId],
        ),
      );
      final encoded = jsonEncode(result.toJson());

      expect(encoded, contains('[local_path_redacted]'));
      for (final leakedSuffix in [
        'My Private',
        'Team Share',
        'title_tail',
        'win_tail',
        'unc_tail',
        'unix_tail',
        'uri_tail',
        'tag_tail',
        'source_tail',
        'canonical_tail',
        'group_tail',
        'edge_tail',
      ]) {
        expect(encoded, isNot(contains(leakedSuffix)), reason: leakedSuffix);
      }
      expect(encoded, isNot(contains('file://')));
    },
  );

  test('read host leaves Drift and whiteboard snapshot unchanged', () async {
    final before = await _persistentProjection(store, repository, fixture);

    final result = await host.readSelection(
      WhiteboardAiReadRequest(
        boardId: fixture.boardId,
        cardIds: [fixture.noteCardId, fixture.sourceCardId],
        sourceIds: [fixture.sourceId],
      ),
    );
    expect(result.status, WhiteboardAiReadStatus.ok);

    final after = await _persistentProjection(store, repository, fixture);
    expect(
      after,
      before,
      reason: 'a read tool call must not mutate Drift or the board snapshot',
    );
  });
}

Future<_Fixture> _seed(
  UnifiedCardRepository repository,
  WhiteboardDriftStore store,
) async {
  const boardId = 'board_w5_read_tools';
  const noteCardId = 'card_read_note';
  const deletedCardId = 'card_deleted_note';
  const deletedSourceId = 'source_deleted';
  final now = DateTime.utc(2026, 8, 21, 8);

  await repository.createTextCard(
    cardId: noteCardId,
    title: 'Read tool note',
    body: 'unified read body at ${r'C:/Users/USER'}',
    tags: const ['research', 'whiteboard'],
    createdAt: now,
  );
  await repository.updateCardMetadata(
    noteCardId,
    presentation: const {
      'private_path': r'C:/Users/USER',
      'secret': 'presentation_secret',
    },
  );
  await repository.createTextCard(
    cardId: deletedCardId,
    title: 'deleted card',
    body: 'deleted card body',
    createdAt: now,
  );
  await repository.softDeleteCard(deletedCardId, at: now);

  final ingestion = _ingestion(now);
  final committed = await repository.commitIngestion(ingestion);

  final snapshot = WhiteboardSnapshot(
    boards: [Board(boardId: boardId, name: 'W5 read board', createdAt: now)],
    sources: [
      SourceContent(
        sourceId: deletedSourceId,
        mediaType: SourceMediaType.text,
        title: 'deleted source',
        currentVersionId: 'version_deleted',
        metadata: const {'secret': 'deleted source body'},
        createdAt: now,
        deletedAt: now,
      ),
    ],
    sourceVersions: [
      SourceVersion(
        versionId: 'version_deleted',
        sourceId: deletedSourceId,
        contentHash: 'deleted_hash',
        objectRef: r'C:/Users/USER',
        createdAt: now,
      ),
    ],
    boardItems: [
      const BoardItem(
        itemId: 'item_note_a',
        boardId: boardId,
        cardId: noteCardId,
        x: 10,
        y: 20,
        viewState: {'secret': 'view_state_secret'},
      ),
      const BoardItem(
        itemId: 'item_note_b',
        boardId: boardId,
        cardId: noteCardId,
        x: 40,
        y: 50,
      ),
      BoardItem(
        itemId: 'item_source',
        boardId: boardId,
        cardId: committed.card.cardId,
        x: 300,
        y: 20,
      ),
      const BoardItem(
        itemId: 'item_deleted',
        boardId: boardId,
        cardId: deletedCardId,
      ),
    ],
    groups: const [
      BoardGroup(
        groupId: 'group_research',
        boardId: boardId,
        name: 'Research',
        style: {'secret': 'group_style_secret'},
      ),
    ],
    groupMembers: const [
      GroupMember(groupId: 'group_research', itemId: 'item_note_a'),
      GroupMember(groupId: 'group_research', itemId: 'item_source', order: 1),
      GroupMember(groupId: 'group_research', itemId: 'item_deleted', order: 2),
    ],
    edges: [
      BoardEdge(
        edgeId: 'edge_related',
        boardId: boardId,
        fromItemId: 'item_note_a',
        toItemId: 'item_source',
        semanticType: 'related',
        label: 'supports',
        style: const {'secret': 'edge_style_secret'},
        createdAt: now,
      ),
      BoardEdge(
        edgeId: 'edge_deleted',
        boardId: boardId,
        fromItemId: 'item_note_b',
        toItemId: 'item_source',
        createdAt: now,
        deletedAt: now,
      ),
    ],
    updatedAt: now,
  );
  expect(await store.save(boardId, snapshot), isTrue);

  return _Fixture(
    boardId: boardId,
    noteCardId: noteCardId,
    sourceCardId: committed.card.cardId,
    deletedCardId: deletedCardId,
    sourceId: committed.source.sourceId,
    deletedSourceId: deletedSourceId,
  );
}

IngestionResult _ingestion(DateTime now) {
  const sourceId = 'source_web_read_tool';
  const versionId = 'version_web_read_tool';
  final source = SourceContent(
    sourceId: sourceId,
    mediaType: SourceMediaType.web,
    title: 'Read tool source',
    origin: SourceOrigin.externalLink,
    provider: 'web',
    canonicalId: 'example-read-tool',
    mimeType: 'text/html',
    currentVersionId: versionId,
    contentHash: 'read_tool_hash',
    objectRef: 'objects/sources/source_web_read_tool/version.json',
    metadata: const {
      'canonical_url': 'https://example.com/read-tool',
      'secret': 'source_metadata_secret',
      'private_path': r'C:/Users/USER',
    },
    createdAt: now,
    updatedAt: now,
  );
  final version = SourceVersion(
    versionId: versionId,
    sourceId: sourceId,
    contentHash: 'read_tool_hash',
    objectRef: source.objectRef!,
    parserVersion: 'test-v1',
    createdAt: now,
  );
  return IngestionResult(
    canonicalUrl: 'https://example.com/read-tool',
    originalUrl: 'https://example.com/read-tool?utm_source=test',
    provider: 'web',
    status: IngestionStatus.ok,
    source: source,
    sourceVersion: version.toJson(),
    hasBody: true,
    metadata: const {'body_text': 'source body', 'body_excerpt': 'source body'},
    resolvedAt: now,
  );
}

Future<String> _persistentProjection(
  WhiteboardDriftStore store,
  UnifiedCardRepository repository,
  _Fixture fixture,
) async {
  final board = await store.load(fixture.boardId);
  expect(board.isSuccess, isTrue);
  final cards = await repository.listCards(
    const CardLibraryQuery(includeDeleted: true, loadDocuments: false),
  );
  final source = await repository.getSource(fixture.sourceId);
  final versions = await repository.listSourceVersions(fixture.sourceId);
  return jsonEncode({
    'snapshot': board.snapshot!.toJson(),
    'cards': cards.map((record) => record.card.toJson()).toList(),
    'source': source?.toJson(),
    'versions': versions.map((version) => version.toJson()).toList(),
  });
}

class _Fixture {
  const _Fixture({
    required this.boardId,
    required this.noteCardId,
    required this.sourceCardId,
    required this.deletedCardId,
    required this.sourceId,
    required this.deletedSourceId,
  });

  final String boardId;
  final String noteCardId;
  final String sourceCardId;
  final String deletedCardId;
  final String sourceId;
  final String deletedSourceId;
}
