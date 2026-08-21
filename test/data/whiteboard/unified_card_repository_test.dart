import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/thumbnail/safe_thumbnail_resolver.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/source_content.dart';

class _RecordingThumbnailResolver implements ThumbnailResolver {
  _RecordingThumbnailResolver(this.result, {this.gate});

  final ResolvedThumbnail result;
  final Completer<void>? gate;
  final List<ThumbnailResolveRequest> requests = [];

  @override
  Future<ResolvedThumbnail> resolve(ThumbnailResolveRequest request) async {
    requests.add(request);
    await gate?.future;
    return result;
  }
}

void main() {
  late Directory tempDir;
  late File dbFile;
  late AppDatabase db;
  late UnifiedCardRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('f0_repository_');
    dbFile = File('${tempDir.path}/repository.sqlite');
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: tempDir);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('clean database text card is immediately visible in unified list',
      () async {
    final created = await repository.createTextCard(
      title: '第一张卡',
      body: '立即可见的正文',
      tags: const ['想法'],
    );

    final listed = await repository.listCards();
    expect(listed, hasLength(1));
    expect(listed.single.card.cardId, created.cardId);
    expect(listed.single.card.body, '立即可见的正文');
  });

  test('rich text keeps identity, updates searchable projection and restarts',
      () async {
    final card = await repository.createTextCard(title: '旧标题');
    const document = RichTextDocument(blocks: [
      RichTextBlock(type: BlockType.heading, text: '新标题'),
      RichTextBlock(type: BlockType.paragraph, text: '可搜索正文关键词'),
    ]);

    final saved = await repository.saveRichText(card.cardId, document);
    expect(saved.cardId, card.cardId);
    expect(saved.title, '新标题');
    expect(
      await repository.listCards(
        const CardLibraryQuery(search: '正文关键词'),
      ),
      hasLength(1),
    );

    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    final restarted = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
    );
    final recovered = await restarted.getCard(card.cardId);
    expect(recovered, isNotNull);
    expect(recovered!.card.cardId, card.cardId);
    expect(recovered.documentState, CardDocumentState.available);
    expect(recovered.document!.toPlainText(), contains('可搜索正文关键词'));
  });

  test('fetch result creates no truth until explicitly committed', () async {
    final result = _ingestion(hash: 'hash_a', body: '抓取预览');

    expect(await repository.listCards(), isEmpty);
    expect(await repository.getSource(result.source!.sourceId), isNull);

    final committed = await repository.commitIngestion(result);
    expect(committed.cardCreated, isTrue);
    expect(await repository.listCards(), hasLength(1));
    expect(await repository.getSource(result.source!.sourceId), isNotNull);
  });

  test('same canonical content is idempotent', () async {
    final first = await repository.commitIngestion(
      _ingestion(hash: 'same_hash', body: '相同内容'),
    );
    final second = await repository.commitIngestion(
      _ingestion(hash: 'same_hash', body: '相同内容'),
    );

    expect(second.versionIsNew, isFalse);
    expect(second.cardCreated, isFalse);
    expect(second.card.cardId, first.card.cardId);
    expect(await repository.listCards(), hasLength(1));
    expect(
      await repository.listSourceVersions(first.source.sourceId),
      hasLength(1),
    );
  });

  test('changed content adds SourceVersion without duplicating Card', () async {
    final first = await repository.commitIngestion(
      _ingestion(hash: 'hash_v1', body: '版本一'),
    );
    final second = await repository.commitIngestion(
      _ingestion(hash: 'hash_v2', body: '版本二'),
    );

    expect(second.versionIsNew, isTrue);
    expect(second.card.cardId, first.card.cardId);
    expect(await repository.listCards(), hasLength(1));
    expect(
      await repository.listSourceVersions(first.source.sourceId),
      hasLength(2),
    );
  });

  test('safe thumbnail projection persists on the existing Source card',
      () async {
    final thumbnailFile = File('${tempDir.path}/trusted-thumbnail.png');
    await thumbnailFile.writeAsBytes([1], flush: true);
    const objectRef =
        'objects/thumbnails/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png';
    final candidateHash = SafeThumbnailResolver.candidateHashFor(
      'https://example.com/cover.png',
      'https://example.com/f0',
    )!;
    final resolver = _RecordingThumbnailResolver(
      ResolvedThumbnail.available(
        file: thumbnailFile,
        objectRef: objectRef,
        width: 40,
        height: 24,
        candidateHash: candidateHash,
      ),
    );
    repository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      thumbnailResolver: resolver,
    );
    final committed = await repository.commitIngestion(
      _ingestion(hash: 'thumbnail_projection', body: '缩略图投影'),
    );
    final before = await repository.getCard(
      committed.card.cardId,
      loadDocument: false,
    );

    final resolved = await repository.resolveThumbnail(before!);

    expect(resolved.isAvailable, isTrue);
    expect(resolver.requests, hasLength(1));
    expect(
        resolver.requests.single.candidateUrl, 'https://example.com/cover.png');
    expect(resolver.requests.single.cachedObjectRef, isNull);
    final recovered = await repository.getCard(
      committed.card.cardId,
      loadDocument: false,
    );
    expect(recovered!.card.cardId, committed.card.cardId);
    expect(recovered.card.sourceId, committed.source.sourceId);
    expect(
      recovered.card.updatedAt,
      before.card.updatedAt,
      reason: 'a rebuildable thumbnail must not masquerade as a card edit',
    );
    expect(recovered.card.presentation['thumbnail_ref'], objectRef);
    expect(
      recovered.card.presentation['thumbnail_version_id'],
      committed.version.versionId,
    );
    expect(
      recovered.card.presentation['thumbnail_candidate_hash'],
      candidateHash,
    );
  });

  test('background thumbnail projection cannot overwrite a concurrent edit',
      () async {
    final gate = Completer<void>();
    final resolver = _RecordingThumbnailResolver(
      ResolvedThumbnail.available(
        file: File('${tempDir.path}/trusted-concurrent.png'),
        objectRef:
            'objects/thumbnails/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.png',
        width: 40,
        height: 24,
        candidateHash: SafeThumbnailResolver.candidateHashFor(
          'https://example.com/cover.png',
          'https://example.com/f0',
        )!,
      ),
      gate: gate,
    );
    repository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      thumbnailResolver: resolver,
    );
    final committed = await repository.commitIngestion(
      _ingestion(hash: 'thumbnail_concurrent', body: '原正文'),
    );
    final before = await repository.getCard(
      committed.card.cardId,
      loadDocument: false,
    );
    final resolving = repository.resolveThumbnail(before!);
    expect(resolver.requests, hasLength(1));

    final edited = await repository.updateCardMetadata(
      committed.card.cardId,
      title: '用户并发编辑后的标题',
      body: '用户并发编辑后的正文',
    );
    gate.complete();
    await resolving;

    final recovered = await repository.getCard(
      committed.card.cardId,
      loadDocument: false,
    );
    expect(recovered!.card.title, edited.title);
    expect(recovered.card.body, edited.body);
    expect(
      recovered.card.updatedAt?.millisecondsSinceEpoch,
      edited.updatedAt?.millisecondsSinceEpoch,
    );
    expect(recovered.card.presentation['thumbnail_ref'], isNotNull);
  });

  test('stale SourceVersion thumbnail cannot project after a new version',
      () async {
    final gate = Completer<void>();
    final resolver = _RecordingThumbnailResolver(
      ResolvedThumbnail.available(
        file: File('${tempDir.path}/stale-version.png'),
        objectRef:
            'objects/thumbnails/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee.png',
        width: 40,
        height: 24,
        candidateHash: SafeThumbnailResolver.candidateHashFor(
          'https://example.com/cover.png',
          'https://example.com/f0',
        )!,
      ),
      gate: gate,
    );
    repository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      thumbnailResolver: resolver,
    );
    final first = await repository.commitIngestion(
      _ingestion(hash: 'thumbnail_version_v1', body: '版本一'),
    );
    final before = await repository.getCard(
      first.card.cardId,
      loadDocument: false,
    );
    final resolving = repository.resolveThumbnail(before!);
    expect(resolver.requests, hasLength(1));

    final second = await repository.commitIngestion(
      _ingestion(hash: 'thumbnail_version_v2', body: '版本二'),
    );
    gate.complete();
    final stale = await resolving;

    expect(stale.status, ThumbnailResolveStatus.missing);
    final recovered = await repository.getCard(
      first.card.cardId,
      loadDocument: false,
    );
    expect(
        recovered!.currentSourceVersion?.versionId, second.version.versionId);
    expect(recovered.card.presentation['thumbnail_ref'], isNull);
  });

  test('same SourceVersion cannot accept an older thumbnail candidate',
      () async {
    final gate = Completer<void>();
    final resolver = _RecordingThumbnailResolver(
      ResolvedThumbnail.available(
        file: File('${tempDir.path}/stale-candidate.png'),
        objectRef:
            'objects/thumbnails/9999999999999999999999999999999999999999999999999999999999999999.png',
        width: 40,
        height: 24,
        candidateHash: SafeThumbnailResolver.candidateHashFor(
          'https://example.com/cover.png',
          'https://example.com/f0',
        )!,
      ),
      gate: gate,
    );
    repository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      thumbnailResolver: resolver,
    );
    final first = await repository.commitIngestion(
      _ingestion(hash: 'same_body_hash', body: '相同正文'),
    );
    final before = await repository.getCard(
      first.card.cardId,
      loadDocument: false,
    );
    final resolving = repository.resolveThumbnail(before!);
    expect(resolver.requests, hasLength(1));

    final second = await repository.commitIngestion(
      _ingestion(
        hash: 'same_body_hash',
        body: '相同正文',
        ogImage: 'https://example.com/new-cover.png',
      ),
    );
    expect(second.version.versionId, first.version.versionId);
    gate.complete();
    final stale = await resolving;

    expect(stale.status, ThumbnailResolveStatus.missing);
    final recovered = await repository.getCard(
      first.card.cardId,
      loadDocument: false,
    );
    expect(recovered!.card.presentation['thumbnail_ref'], isNull);
    expect(
      recovered.card.presentation['thumbnail'],
      'https://example.com/new-cover.png',
    );
  });

  test('startup recovery restores a Source object backup after interruption',
      () async {
    final committed = await repository.commitIngestion(
      _ingestion(hash: 'recover_source', body: 'source object body'),
    );
    final target = File(
      '${tempDir.path}${Platform.pathSeparator}'
      '${committed.version.objectRef.replaceAll('/', Platform.pathSeparator)}',
    );
    final original = jsonDecode(await target.readAsString());
    await target.rename('${target.path}.bak');
    await File('${target.path}.tmp').writeAsString('{broken', flush: true);

    await repository.recoverFileReplacements();

    expect(jsonDecode(await target.readAsString()), original);
    expect(await File('${target.path}.tmp').exists(), isFalse);
    expect(await File('${target.path}.bak').exists(), isFalse);
  });

  test('delete BoardItem does not delete Card, Source, or RichText', () async {
    final committed = await repository.commitIngestion(
      _ingestion(hash: 'placed', body: '上板内容'),
    );
    await repository.saveRichText(
      committed.card.cardId,
      const RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: '持久富文本'),
      ]),
    );
    await db.customStatement(
      "INSERT INTO whiteboard_boards(id,name,created_at) VALUES ('board_f0','F0',1)",
    );
    await db.customStatement(
      "INSERT INTO whiteboard_board_items(id,board_id,card_id) "
      "VALUES ('item_f0','board_f0','${committed.card.cardId}')",
    );
    expect(await repository.isCardPlaced(committed.card.cardId), isTrue);

    await db.customStatement(
      "DELETE FROM whiteboard_board_items WHERE id='item_f0'",
    );

    expect(await repository.isCardPlaced(committed.card.cardId), isFalse);
    expect(await repository.getSource(committed.source.sourceId), isNotNull);
    final card = await repository.getCard(committed.card.cardId);
    expect(card, isNotNull);
    expect(card!.documentState, CardDocumentState.available);
  });

  test('missing and corrupt rich text states are reported honestly', () async {
    final card = await repository.createTextCard(
      title: '降级状态',
      body: '数据库投影仍在',
    );
    expect(
      (await repository.getCard(card.cardId))!.documentState,
      CardDocumentState.missing,
    );

    final dir = Directory(
        '${repository.richTextStorage.baseDir.path}/card_${card.cardId}');
    await dir.create(recursive: true);
    await File('${dir.path}/rich_text.json').writeAsString('{broken');
    final corrupt = await repository.getCard(card.cardId);
    expect(corrupt!.documentState, CardDocumentState.corrupt);
    expect(corrupt.card.body, '数据库投影仍在');
  });

  test('soft delete and restore preserve stable identity and files', () async {
    final card = await repository.createTextCard(title: '可恢复');
    await repository.saveRichText(
        card.cardId,
        const RichTextDocument(blocks: [
          RichTextBlock(type: BlockType.paragraph, text: '不被删除'),
        ]));

    expect(await repository.softDeleteCard(card.cardId), isTrue);
    expect(await repository.getCard(card.cardId), isNull);
    expect(await repository.listCards(), isEmpty);
    expect(await repository.restoreCard(card.cardId), isTrue);

    final restored = await repository.getCard(card.cardId);
    expect(restored!.card.cardId, card.cardId);
    expect(restored.document!.toPlainText(), '不被删除');
  });

  test('kind, tag, source type, search and board placement filters compose',
      () async {
    final note = await repository.createTextCard(
      title: '研究笔记',
      body: '统一仓库',
      tags: const ['研究'],
    );
    final source = await repository.commitIngestion(
      _ingestion(hash: 'filter_hash', body: '网页正文'),
    );
    await db.customStatement(
      "INSERT INTO whiteboard_boards(id,name,created_at) VALUES ('board_filter','筛选',1)",
    );
    await db.customStatement(
      "INSERT INTO whiteboard_board_items(id,board_id,card_id) "
      "VALUES ('item_filter','board_filter','${note.cardId}')",
    );

    expect(
      await repository.listCards(const CardLibraryQuery(
        kinds: {CardKind.note},
        tags: {'研究'},
        search: '统一',
        boardId: 'board_filter',
        placedOnBoard: true,
      )),
      hasLength(1),
    );
    final web = await repository.listCards(const CardLibraryQuery(
      sourceTypes: {SourceMediaType.web},
    ));
    expect(web.single.card.cardId, source.card.cardId);
  });

  test('source object reader returns body and honest missing state', () async {
    final committed = await repository.commitIngestion(
      _ingestion(hash: 'object_reader', body: '可研读的完整正文'),
    );
    final available = await repository.getSourceObject(committed.version);
    expect(available.state, SourceObjectState.available);
    expect(available.bodyText, '可研读的完整正文');

    final missing = await repository.getSourceObject(SourceVersion(
      versionId: 'ver_missing',
      sourceId: committed.source.sourceId,
      contentHash: 'missing',
      objectRef: 'objects/sources/missing/version.json',
      createdAt: DateTime.utc(2026, 8, 19),
    ));
    expect(missing.state, SourceObjectState.missing);
  });

  test('all test persistence stays inside an explicit temporary directory',
      () async {
    await repository.createTextCard(title: '隔离测试');
    expect(dbFile.path, startsWith(tempDir.path));
    expect(repository.whiteboardRoot.path, tempDir.path);
  });
}

IngestionResult _ingestion({
  required String hash,
  required String body,
  String ogImage = 'https://example.com/cover.png',
}) {
  final now = DateTime.utc(2026, 8, 18, 12);
  const sourceId = 'src_web_f0_example';
  final versionId = 'ver_web_f0_example_$hash';
  final source = SourceContent(
    sourceId: sourceId,
    mediaType: SourceMediaType.web,
    title: 'F0 网页',
    origin: SourceOrigin.externalLink,
    provider: 'web',
    currentVersionId: versionId,
    contentHash: hash,
    objectRef: 'ingestion/$sourceId/$versionId.html',
    metadata: {
      'canonical_url': 'https://example.com/f0',
      'og_image': ogImage,
    },
    createdAt: now,
    updatedAt: now,
  );
  final version = SourceVersion(
    versionId: versionId,
    sourceId: sourceId,
    contentHash: hash,
    objectRef: source.objectRef!,
    parserVersion: 'test-v1',
    createdAt: now,
  );
  return IngestionResult(
    canonicalUrl: 'https://example.com/f0',
    originalUrl: 'https://example.com/f0?utm_source=test',
    provider: 'web',
    status: IngestionStatus.ok,
    source: source,
    sourceVersion: version.toJson(),
    hasBody: true,
    metadata: {
      'body_text': body,
      'body_excerpt': body,
    },
    resolvedAt: now,
  );
}
