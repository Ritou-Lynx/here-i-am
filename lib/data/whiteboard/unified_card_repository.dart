/// Unified whiteboard content repository (F0 data convergence).
///
/// Drift owns Card / Source / SourceVersion identity and query projections.
/// Rich-text documents and source bodies remain filesystem objects referenced
/// by stable ids. UI code must consume this repository instead of querying
/// MemoryCards directly or treating a JSON directory as a card library.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as path_api;

import 'package:memex/data/whiteboard/thumbnail/safe_thumbnail_resolver.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/anchor_contract.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/recoverable_file_exchange.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_storage.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/domain/whiteboard/video/time_range_anchor_spec.dart';
import 'package:memex/domain/whiteboard/whiteboard_ids.dart';

/// Filesystem availability of a card's rich-text body.
enum CardDocumentState { available, missing, corrupt }

/// Filesystem availability of an immutable SourceVersion object.
enum SourceObjectState { available, missing, corrupt }

/// A recovered SourceVersion payload. Drift remains the identity authority;
/// this record only exposes the immutable body/metadata projection.
class SourceObjectRecord {
  const SourceObjectRecord({required this.state, this.payload});

  final SourceObjectState state;
  final Map<String, dynamic>? payload;

  String? get bodyText => payload?['body_text'] as String?;
  Map<String, dynamic> get metadata =>
      (payload?['metadata'] as Map<String, dynamic>?) ?? const {};
}

/// A unified card projection returned to all card-library consumers.
class UnifiedCardRecord {
  const UnifiedCardRecord({
    required this.card,
    this.source,
    this.currentSourceVersion,
    this.document,
    required this.documentState,
    required this.isPlaced,
  });

  final CardContract card;
  final SourceContent? source;
  final SourceVersion? currentSourceVersion;
  final RichTextDocument? document;
  final CardDocumentState documentState;
  final bool isPlaced;

  String? get thumbnail => card.presentation['thumbnail'] as String?;
}

/// Filters for [UnifiedCardRepository.listCards].
class CardLibraryQuery {
  const CardLibraryQuery({
    this.kinds,
    this.tags,
    this.sourceTypes,
    this.search,
    this.boardId,
    this.placedOnBoard,
    this.includeDeleted = false,
    this.loadDocuments = false,
    this.limit,
  });

  final Set<CardKind>? kinds;
  final Set<String>? tags;
  final Set<SourceMediaType>? sourceTypes;
  final String? search;
  final String? boardId;
  final bool? placedOnBoard;
  final bool includeDeleted;
  final bool loadDocuments;
  final int? limit;
}

/// Result of atomically committing one confirmed ingestion result.
class IngestionCommitResult {
  const IngestionCommitResult({
    required this.source,
    required this.version,
    required this.versionIsNew,
    required this.card,
    required this.cardCreated,
    required this.cardRestored,
  });

  final SourceContent source;
  final SourceVersion version;
  final bool versionIsNew;
  final CardContract card;
  final bool cardCreated;
  final bool cardRestored;
}

/// Deterministic transaction boundaries used only by repository fault tests.
enum UnifiedCardRepositoryFaultPoint {
  annotationAfterMemoryCardInsert,
  annotationAfterExtrasInsert,
  ingestionDuringObjectExchange,
  ingestionAfterObjectWriteBeforeVersionInsert,
  ingestionAfterVersionInsert,
  ingestionAfterTransactionCommitBeforeIntentCleanup,
}

typedef UnifiedCardRepositoryFaultInjector = Future<void> Function(
    UnifiedCardRepositoryFaultPoint point);

/// Test-only sentinel that models a process exit without running compensation.
///
/// Production callers never throw this. Repository fault tests use it to prove
/// that startup intent reconciliation repairs the cross-file/DB crash window.
class UnifiedCardRepositorySimulatedProcessExit implements Exception {
  const UnifiedCardRepositorySimulatedProcessExit();
}

class _SourceObjectWriteGuard {
  static const int maxSnapshotFileBytes = 4 * 1024 * 1024;
  static const int maxSnapshotTotalBytes = 8 * 1024 * 1024;

  const _SourceObjectWriteGuard({
    required this.objectRef,
    required this.snapshots,
  });

  final String objectRef;
  final List<_FileSnapshot> snapshots;

  Map<String, dynamic> get intentSnapshot => {
        'final': snapshots[0].toJson(),
        'temp': snapshots[1].toJson(),
        'backup': snapshots[2].toJson(),
      };

  static Future<_SourceObjectWriteGuard> capture(
    File target,
    String objectRef,
  ) async {
    final temp = RecoverableFileExchange.tempFor(target);
    final backup = RecoverableFileExchange.backupFor(target);
    final snapshots = await Future.wait(
      <File>[target, temp, backup].map(_FileSnapshot.capture),
    );
    final totalBytes = snapshots.fold<int>(
      0,
      (total, snapshot) => total + (snapshot.contents?.length ?? 0),
    );
    if (totalBytes > maxSnapshotTotalBytes) {
      throw StateError('Source object recovery snapshot exceeds safe limit');
    }
    return _SourceObjectWriteGuard(objectRef: objectRef, snapshots: snapshots);
  }

  static _SourceObjectWriteGuard? fromIntent(
    File target,
    String objectRef,
    Object? raw,
  ) {
    if (raw is! Map || raw.length != 3) return null;
    final snapshots = <_FileSnapshot?>[
      _FileSnapshot.fromJson(target, raw['final']),
      _FileSnapshot.fromJson(
        RecoverableFileExchange.tempFor(target),
        raw['temp'],
      ),
      _FileSnapshot.fromJson(
        RecoverableFileExchange.backupFor(target),
        raw['backup'],
      ),
    ];
    if (snapshots.any((snapshot) => snapshot == null)) return null;
    final totalBytes = snapshots.fold<int>(
      0,
      (total, snapshot) => total + (snapshot?.contents?.length ?? 0),
    );
    if (totalBytes > maxSnapshotTotalBytes) return null;
    return _SourceObjectWriteGuard(
      objectRef: objectRef,
      snapshots: snapshots.cast<_FileSnapshot>(),
    );
  }

  Future<void> removeCreatedFilesIfUnreferenced(AppDatabase db) async {
    final versionReference = await (db.select(
      db.whiteboardSourceVersions,
    )..where((row) => row.objectRef.equals(objectRef)))
        .getSingleOrNull();
    final sourceReference = await (db.select(
      db.whiteboardSources,
    )..where((row) => row.objectRef.equals(objectRef)))
        .getSingleOrNull();
    final isReferenced = versionReference != null || sourceReference != null;
    if (isReferenced) return;
    await restoreSnapshots();
  }

  Future<void> restoreSnapshots() async {
    for (final snapshot in snapshots) {
      if (snapshot.contents != null) {
        await snapshot.file.parent.create(recursive: true);
        await snapshot.file.writeAsBytes(snapshot.contents!, flush: true);
      } else if (await snapshot.file.exists()) {
        await snapshot.file.delete();
      }
    }
  }
}

class _FileSnapshot {
  const _FileSnapshot(this.file, this.contents);

  final File file;
  final List<int>? contents;

  Map<String, dynamic> toJson() => {
        'existed': contents != null,
        if (contents != null) ...{
          'bytes_base64': base64Encode(contents!),
          'length': contents!.length,
          'sha256': sha256.convert(contents!).toString(),
        },
      };

  static _FileSnapshot? fromJson(File file, Object? raw) {
    if (raw is! Map || raw['existed'] is! bool) return null;
    if (raw['existed'] == false) {
      if (raw.length != 1) return null;
      return _FileSnapshot(file, null);
    }
    final encoded = raw['bytes_base64'];
    final length = raw['length'];
    final expectedHash = raw['sha256'];
    if (raw.length != 4 ||
        encoded is! String ||
        length is! int ||
        length < 0 ||
        length > _SourceObjectWriteGuard.maxSnapshotFileBytes ||
        expectedHash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedHash)) {
      return null;
    }
    final maxEncodedLength = ((length + 2) ~/ 3) * 4;
    if (encoded.length != maxEncodedLength) return null;
    try {
      final decoded = base64Decode(encoded);
      if (decoded.length != length ||
          sha256.convert(decoded).toString() != expectedHash) {
        return null;
      }
      return _FileSnapshot(file, decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<_FileSnapshot> capture(File file) async {
    if (!await file.exists()) return _FileSnapshot(file, null);
    final length = await file.length();
    if (length > _SourceObjectWriteGuard.maxSnapshotFileBytes) {
      throw StateError('Source object recovery snapshot exceeds safe limit');
    }
    final contents = await file.readAsBytes();
    if (contents.length > _SourceObjectWriteGuard.maxSnapshotFileBytes) {
      throw StateError('Source object recovery snapshot exceeds safe limit');
    }
    return _FileSnapshot(file, contents);
  }
}

class _SourceObjectIntentReconciliation {
  const _SourceObjectIntentReconciliation({
    required this.protectedObjectPaths,
    required this.hasUnresolvedIntent,
  });

  final Set<String> protectedObjectPaths;
  final bool hasUnresolvedIntent;
}

/// Repository for the single production Card / Source data truth.
///
/// The database is constructor-injected. This file intentionally has no
/// dependency on MemexRouter or AppDatabase.instance.
class UnifiedCardRepository {
  static final Map<String, Future<void>> _sourceObjectCommitLocks = {};
  static const int _maxSourceObjectIntentBytes = 12 * 1024 * 1024;

  UnifiedCardRepository({
    required this.db,
    required this.whiteboardRoot,
    RichTextStorage? richTextStorage,
    this.thumbnailResolver,
    this.faultInjector,
    this.sourceObjectPathCanonicalizer,
  }) : richTextStorage = richTextStorage ??
            RichTextStorage(Directory(_join(whiteboardRoot.path, 'rich_text')));

  final AppDatabase db;
  final Directory whiteboardRoot;
  final RichTextStorage richTextStorage;
  final ThumbnailResolver? thumbnailResolver;
  final UnifiedCardRepositoryFaultInjector? faultInjector;
  final Future<String> Function(String path)? sourceObjectPathCanonicalizer;

  /// Repairs interrupted rich-text and Source-object exchanges at startup.
  Future<void> recoverFileReplacements() async {
    await richTextStorage.recoverAll();
    final reconciliation = await _reconcileSourceObjectIntents();
    final sourceRoot = _sourceObjectRoot;
    if (!await sourceRoot.exists()) return;
    if (reconciliation.hasUnresolvedIntent ||
        !await _isDirectoryContained(
          root: whiteboardRoot,
          child: sourceRoot,
        )) {
      return;
    }
    final targets = <String>{};
    await for (final entity in sourceRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      var path = entity.path;
      if (path.endsWith('.tmp') || path.endsWith('.bak')) {
        path = path.substring(0, path.length - 4);
      }
      if (path.endsWith('.json')) targets.add(path);
    }
    for (final path in targets) {
      final target = File(path);
      if (reconciliation.protectedObjectPaths.contains(target.absolute.path)) {
        continue;
      }
      if (!await _isSafeContainedSourceObjectFile(target)) continue;
      await RecoverableFileExchange.recover(
        target,
        validator: _isValidJsonMap,
      );
    }
  }

  Future<_SourceObjectIntentReconciliation>
      _reconcileSourceObjectIntents() async {
    final protectedObjectPaths = <String>{};
    var hasUnresolvedIntent = false;
    final intentRoot = _sourceObjectIntentRoot;
    if (!await intentRoot.exists()) {
      return _SourceObjectIntentReconciliation(
        protectedObjectPaths: protectedObjectPaths,
        hasUnresolvedIntent: false,
      );
    }
    if (!await _isDirectoryContained(
      root: whiteboardRoot,
      child: intentRoot,
    )) {
      return _SourceObjectIntentReconciliation(
        protectedObjectPaths: protectedObjectPaths,
        hasUnresolvedIntent: true,
      );
    }
    final targets = <String>{};
    await for (final entity in intentRoot.list(followLinks: false)) {
      if (entity is! File && entity is! Link) continue;
      var path = entity.path;
      if (path.endsWith('.tmp') || path.endsWith('.bak')) {
        path = path.substring(0, path.length - 4);
      }
      if (path.endsWith('.json')) targets.add(path);
    }
    for (final path in targets) {
      final intentFile = File(path);
      final candidates = <File>[
        intentFile,
        RecoverableFileExchange.tempFor(intentFile),
        RecoverableFileExchange.backupFor(intentFile),
      ];
      try {
        final candidateContents = <File, String>{};
        var candidateBoundaryUnknown = false;
        for (final candidate in candidates) {
          final type = await FileSystemEntity.type(
            candidate.path,
            followLinks: false,
          );
          if (type == FileSystemEntityType.notFound) continue;
          if (type != FileSystemEntityType.file) {
            candidateBoundaryUnknown = true;
            continue;
          }
          final contents = await _readBoundedIntentCandidate(candidate);
          if (contents == null) {
            candidateBoundaryUnknown = true;
            continue;
          }
          candidateContents[candidate] = contents;
        }

        if (candidateBoundaryUnknown) {
          hasUnresolvedIntent = true;
          continue;
        }

        final validObjectRefs = <String>{};
        for (final contents in candidateContents.values) {
          if (!_isValidSourceObjectIntentJson(contents)) continue;
          final decoded = jsonDecode(contents) as Map<String, dynamic>;
          validObjectRefs.add(decoded['object_ref'] as String);
        }

        if (validObjectRefs.length > 1) {
          hasUnresolvedIntent = true;
          continue;
        }

        if (validObjectRefs.isEmpty) {
          var allCandidatesIdentifyManagedObjects =
              candidateContents.isNotEmpty;
          for (final contents in candidateContents.values) {
            try {
              final decoded = jsonDecode(contents);
              final objectRef = decoded is Map<String, dynamic>
                  ? _safeManagedSourceObjectRef(decoded['object_ref'])
                  : null;
              if (objectRef == null) {
                allCandidatesIdentifyManagedObjects = false;
              } else {
                protectedObjectPaths.add(_objectFile(objectRef).absolute.path);
              }
            } catch (_) {
              allCandidatesIdentifyManagedObjects = false;
            }
          }
          if (!allCandidatesIdentifyManagedObjects) {
            hasUnresolvedIntent = true;
          }
          continue;
        }

        final objectRef = validObjectRefs.single;
        final objectFile = _objectFile(objectRef);
        protectedObjectPaths.add(objectFile.absolute.path);
        if (!await _isSafeContainedSourceObjectFile(objectFile)) {
          hasUnresolvedIntent = true;
          continue;
        }

        final recovered = await RecoverableFileExchange.recover(
          intentFile,
          validator: _isValidSourceObjectIntentJson,
          maxBytes: _maxSourceObjectIntentBytes,
        );
        if (!recovered || !await intentFile.exists()) {
          hasUnresolvedIntent = true;
          continue;
        }
        final recoveredContents = await _readBoundedIntentCandidate(intentFile);
        if (recoveredContents == null ||
            !_isValidSourceObjectIntentJson(recoveredContents)) {
          hasUnresolvedIntent = true;
          continue;
        }
        final decoded = jsonDecode(recoveredContents) as Map<String, dynamic>;
        final guard = _SourceObjectWriteGuard.fromIntent(
          objectFile,
          objectRef,
          decoded['pre_write_snapshot'],
        )!;
        final versionReference = await (db.select(
          db.whiteboardSourceVersions,
        )..where((row) => row.objectRef.equals(objectRef)))
            .getSingleOrNull();
        final sourceReference = await (db.select(
          db.whiteboardSources,
        )..where((row) => row.objectRef.equals(objectRef)))
            .getSingleOrNull();
        if (versionReference == null && sourceReference == null) {
          await guard.restoreSnapshots();
        }
        await _deleteFileExchange(intentFile);
      } catch (_) {
        // Corrupt or unknown intents stay byte-for-byte available for
        // diagnosis and never block reconciliation of independent intents.
        hasUnresolvedIntent = true;
      }
    }
    return _SourceObjectIntentReconciliation(
      protectedObjectPaths: protectedObjectPaths,
      hasUnresolvedIntent: hasUnresolvedIntent,
    );
  }

  /// Returns an active card by stable id, or null when it is absent/deleted.
  Future<UnifiedCardRecord?> getCard(
    String cardId, {
    bool includeDeleted = false,
    bool loadDocument = true,
  }) async {
    final row = await (db.select(
      db.memoryCards,
    )..where((t) => t.id.equals(cardId)))
        .getSingleOrNull();
    final extra = await (db.select(
      db.whiteboardCardExtras,
    )..where((t) => t.cardId.equals(cardId)))
        .getSingleOrNull();
    if (row == null || extra == null) return null;
    if (!includeDeleted && extra.deletedAt != null) return null;

    final source =
        extra.sourceId == null ? null : await _sourceById(extra.sourceId!);
    final currentVersion = source?.currentVersionId == null
        ? null
        : await _versionById(source!.currentVersionId!);
    final placed = await isCardPlaced(cardId);
    final rich =
        loadDocument ? await richTextStorage.loadWithStatus(cardId) : null;
    return UnifiedCardRecord(
      card: _toCard(row, extra),
      source: source,
      currentSourceVersion: currentVersion,
      document: rich?.document,
      documentState: _documentState(rich?.status),
      isPlaced: placed,
    );
  }

  /// Lists cards from Drift. It never scans the rich-text directory.
  Future<List<UnifiedCardRecord>> listCards([
    CardLibraryQuery query = const CardLibraryQuery(),
  ]) async {
    final extras = await db.select(db.whiteboardCardExtras).get();
    final selectedExtras = extras.where((extra) {
      if (!query.includeDeleted && extra.deletedAt != null) return false;
      if (query.kinds != null &&
          !query.kinds!.contains(CardKind.fromString(extra.cardKind))) {
        return false;
      }
      return true;
    }).toList();
    if (selectedExtras.isEmpty) return const [];

    final ids = selectedExtras.map((e) => e.cardId).toList();
    final rows = await (db.select(
      db.memoryCards,
    )..where((t) => t.id.isIn(ids)))
        .get();
    final rowsById = {for (final row in rows) row.id: row};

    final sourceIds = selectedExtras
        .map((e) => e.sourceId)
        .whereType<String>()
        .toSet()
        .toList();
    final sourceRows = sourceIds.isEmpty
        ? <WhiteboardSource>[]
        : await (db.select(
            db.whiteboardSources,
          )..where((t) => t.id.isIn(sourceIds)))
            .get();
    final sourcesById = {for (final row in sourceRows) row.id: _toSource(row)};

    Set<String> placedIds = const {};
    if (query.boardId != null || query.placedOnBoard != null) {
      final itemQuery = db.select(db.whiteboardBoardItems);
      if (query.boardId != null) {
        itemQuery.where((t) => t.boardId.equals(query.boardId!));
      }
      placedIds = (await itemQuery.get()).map((e) => e.cardId).toSet();
    }

    final normalizedSearch = query.search?.trim().toLowerCase() ?? '';
    final normalizedTags =
        query.tags?.map((tag) => tag.trim().toLowerCase()).toSet();
    final records = <UnifiedCardRecord>[];
    for (final extra in selectedExtras) {
      final row = rowsById[extra.cardId];
      if (row == null) continue;
      final card = _toCard(row, extra);
      final source =
          extra.sourceId == null ? null : sourcesById[extra.sourceId!];
      if (query.sourceTypes != null &&
          (source == null || !query.sourceTypes!.contains(source.mediaType))) {
        continue;
      }
      if (normalizedTags != null &&
          !normalizedTags.every(
            (tag) => card.tags.any((value) => value.toLowerCase() == tag),
          )) {
        continue;
      }
      if (normalizedSearch.isNotEmpty) {
        final haystack = <String>[
          card.title,
          card.body,
          ...card.tags,
        ].join('\n').toLowerCase();
        if (!haystack.contains(normalizedSearch)) continue;
      }
      final placed = placedIds.contains(card.cardId);
      if (query.placedOnBoard != null && query.placedOnBoard != placed) {
        continue;
      }
      final rich = query.loadDocuments
          ? await richTextStorage.loadWithStatus(card.cardId)
          : null;
      records.add(
        UnifiedCardRecord(
          card: card,
          source: source,
          currentSourceVersion: source?.currentVersionId == null
              ? null
              : await _versionById(source!.currentVersionId!),
          document: rich?.document,
          documentState: _documentState(rich?.status),
          isPlaced: placed,
        ),
      );
    }
    records.sort((a, b) {
      final aTime = a.card.updatedAt ?? a.card.createdAt;
      final bTime = b.card.updatedAt ?? b.card.createdAt;
      final byTime = bTime.compareTo(aTime);
      return byTime != 0 ? byTime : a.card.cardId.compareTo(b.card.cardId);
    });
    final limit = query.limit;
    if (limit != null && records.length > limit) {
      return records.take(limit).toList();
    }
    return records;
  }

  /// Lists the canonical tag vocabulary stored on real Cards.
  ///
  /// Tags remain Card metadata; this method deliberately adds no second tag
  /// table or cache. Results are normalized case-insensitively while keeping
  /// the spelling of the first stored occurrence.
  Future<List<String>> listDistinctTags({bool includeDeleted = false}) async {
    final extras = await db.select(db.whiteboardCardExtras).get();
    final selected = extras
        .where((extra) => includeDeleted || extra.deletedAt == null)
        .toList();
    if (selected.isEmpty) return const [];

    final ids = selected.map((extra) => extra.cardId).toList();
    final existingIds = (await (db.select(
      db.memoryCards,
    )..where((table) => table.id.isIn(ids)))
            .get())
        .map((row) => row.id)
        .toSet();
    final result = <String>[];
    final seen = <String>{};
    for (final extra in selected) {
      if (!existingIds.contains(extra.cardId)) continue;
      for (final tag in _decodeStringList(extra.tagsJson)) {
        final trimmed = tag.trim();
        if (trimmed.isEmpty || !seen.add(trimmed.toLowerCase())) continue;
        result.add(trimmed);
      }
    }
    result.sort((left, right) {
      final byFolded = left.toLowerCase().compareTo(right.toLowerCase());
      return byFolded != 0 ? byFolded : left.compareTo(right);
    });
    return result;
  }

  /// Creates an explicit user-authored text card.
  Future<CardContract> createTextCard({
    String? cardId,
    String title = '',
    String body = '',
    List<String> tags = const [],
    OwnerSpace ownerSpace = OwnerSpace.user,
    CardCreatedBy createdBy = CardCreatedBy.user,
    DateTime? createdAt,
  }) async {
    final id = cardId ?? StableId.generate('card').value;
    final existing = await (db.select(
      db.memoryCards,
    )..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (existing != null) {
      throw StateError('Card already exists: $id');
    }
    final now = (createdAt ?? DateTime.now()).toUtc();
    final card = CardContract(
      cardId: id,
      cardKind: CardKind.note,
      ownerSpace: ownerSpace,
      title: title,
      body: body,
      tags: _normalizeTags(tags),
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
    await db.transaction(() => _insertNewCard(card));
    return card;
  }

  /// Inserts a complete Source-bound video Annotation Card in one transaction.
  Future<CardContract> createVideoAnnotationCard(CardContract card) async {
    if (card.cardKind != CardKind.annotation || card.sourceId == null) {
      throw ArgumentError('Annotation Card requires kind and sourceId');
    }
    final rawAnchor = card.presentation['anchor'];
    if (rawAnchor is! Map) {
      throw ArgumentError('Annotation Card requires an Anchor projection');
    }
    final anchor = AnchorContract.fromJson(
      Map<String, dynamic>.from(rawAnchor),
    );
    if (anchor.sourceId != card.sourceId) {
      throw ArgumentError('Annotation Card Source and Anchor disagree');
    }
    if (anchor.positionKind != PositionKind.timeRange) {
      throw ArgumentError('Video Annotation requires a time_range Anchor');
    }
    final specError = TimeRangeAnchorSpec.validate(anchor.positionSpec);
    if (specError != null) throw ArgumentError(specError);
    final startMs = (anchor.positionSpec['start_ms'] as num).toInt();
    final endMs = (anchor.positionSpec['end_ms'] as num).toInt();
    final isPoint = anchor.positionSpec['is_point'];
    if (isPoint is! bool || isPoint != (startMs == endMs)) {
      throw ArgumentError(
        'time_range is_point must agree with start_ms and end_ms',
      );
    }
    if (card.presentation['anchor_id'] != anchor.anchorId ||
        card.presentation['start_ms'] != anchor.positionSpec['start_ms'] ||
        card.presentation['end_ms'] != anchor.positionSpec['end_ms'] ||
        card.presentation['is_point'] != anchor.positionSpec['is_point']) {
      throw ArgumentError('Annotation Card summary and Anchor disagree');
    }
    return db.transaction(() async {
      if (await _sourceById(card.sourceId!) == null) {
        throw StateError('Source not found: ${card.sourceId}');
      }
      final sourceVersion = await _versionById(anchor.sourceVersionId);
      if (sourceVersion == null || sourceVersion.sourceId != card.sourceId) {
        throw StateError(
          'SourceVersion does not belong to Source: ${anchor.sourceVersionId}',
        );
      }
      final existing = await (db.select(
        db.memoryCards,
      )..where((t) => t.id.equals(card.cardId)))
          .getSingleOrNull();
      if (existing != null) {
        throw StateError('Card already exists: ${card.cardId}');
      }
      await _insertMemoryCardRow(card);
      await _injectFault(
        UnifiedCardRepositoryFaultPoint.annotationAfterMemoryCardInsert,
      );
      await _insertCardExtraRow(card);
      await _injectFault(
        UnifiedCardRepositoryFaultPoint.annotationAfterExtrasInsert,
      );
      return card;
    });
  }

  /// Updates card metadata and its searchable projection in one transaction.
  Future<CardContract> updateCardMetadata(
    String cardId, {
    String? title,
    String? body,
    List<String>? tags,
    CardKind? cardKind,
    Map<String, dynamic>? presentation,
  }) async {
    final current = await getCard(cardId, loadDocument: false);
    if (current == null) throw StateError('Card not found: $cardId');
    final now = DateTime.now().toUtc();
    final updated = _copyCard(
      current.card,
      title: title,
      body: body,
      tags: tags == null ? null : _normalizeTags(tags),
      cardKind: cardKind,
      presentation: presentation,
      updatedAt: now,
    );
    await db.transaction(() => _updateExistingCard(updated));
    return updated;
  }

  /// Saves full rich text and synchronizes title/body/update projections.
  ///
  /// A Drift Card must already exist, so this path cannot create an orphan
  /// rich-text card id. The JSON is written atomically before the projection
  /// transaction; a later read reports a missing/corrupt file honestly.
  /// [preserveEmptyTitle] is reserved for a surface that edits Card title and
  /// body in one document: an explicit empty synthetic title remains empty
  /// instead of being replaced by the first body line. Existing callers keep
  /// the original projection fallback by default.
  Future<CardContract> saveRichText(
    String cardId,
    RichTextDocument document, {
    String? title,
    bool preserveEmptyTitle = false,
  }) async {
    final current = await getCard(cardId, loadDocument: false);
    if (current == null) throw StateError('Card not found: $cardId');
    await richTextStorage.save(cardId, document);
    final projection = document.toPlainText().trim();
    final projectedTitle = title != null && preserveEmptyTitle
        ? title.trim()
        : title?.trim().isNotEmpty == true
            ? title!.trim()
            : _firstNonEmptyLine(projection, fallback: current.card.title);
    return updateCardMetadata(cardId, title: projectedTitle, body: projection);
  }

  /// Associates an existing source with an existing card.
  Future<CardContract> linkSourceToCard(String cardId, String sourceId) async {
    final current = await getCard(cardId, loadDocument: false);
    if (current == null) throw StateError('Card not found: $cardId');
    final source = await _sourceById(sourceId);
    if (source == null) throw StateError('Source not found: $sourceId');
    final now = DateTime.now().toUtc();
    final updated = _copyCard(
      current.card,
      sourceId: sourceId,
      setSourceId: true,
      updatedAt: now,
    );
    await db.transaction(() => _updateExistingCard(updated));
    return updated;
  }

  Future<SourceContent?> getSource(String sourceId) => _sourceById(sourceId);

  /// Returns every thumbnail cache object still referenced by a Card or
  /// Source projection, including soft-deleted rows that may be restored.
  /// Malformed projection JSON fails closed so cache maintenance never guesses
  /// whether an object is safe to remove.
  Future<Set<String>> referencedThumbnailObjectRefs() async {
    final refs = <String>{};
    void collect(String? encoded, String owner) {
      if (encoded == null) return;
      final decoded = _decodeMap(encoded);
      if (decoded == null) {
        throw FormatException('Invalid thumbnail reference projection: $owner');
      }
      final ref = decoded['thumbnail_ref'];
      if (ref is String && ref.trim().isNotEmpty) refs.add(ref.trim());
    }

    final cardRows = await db.select(db.whiteboardCardExtras).get();
    for (final row in cardRows) {
      collect(row.presentationJson, 'card:${row.cardId}');
    }
    final sourceRows = await db.select(db.whiteboardSources).get();
    for (final row in sourceRows) {
      collect(row.metadataJson, 'source:${row.id}');
    }
    return Set.unmodifiable(refs);
  }

  /// Resolves a Source card thumbnail through the injected safe projection.
  /// Raw `thumbnail` / `og_image` values remain untrusted download candidates;
  /// UI only receives [ResolvedThumbnail.file] after the resolver has produced
  /// and integrity-checked a content-addressed `thumbnail_ref`.
  Future<ResolvedThumbnail> resolveThumbnail(UnifiedCardRecord record) async {
    final resolver = thumbnailResolver;
    final source = record.source;
    final versionId =
        record.currentSourceVersion?.versionId ?? source?.currentVersionId;
    if (resolver == null || source == null || versionId == null) {
      return const ResolvedThumbnail.missing();
    }
    final presentation = record.card.presentation;
    final sourceMetadata = source.metadata;
    final candidate = _firstString([
      sourceMetadata['og_image'],
      sourceMetadata['thumbnail_url'],
      presentation['thumbnail'],
    ]);
    final cachedRef = _firstString([
      presentation['thumbnail_ref'],
      sourceMetadata['thumbnail_ref'],
    ]);
    final cachedVersion = presentation['thumbnail_version_id'] as String? ??
        sourceMetadata['thumbnail_version_id'] as String?;
    final resolved = await resolver.resolve(
      ThumbnailResolveRequest(
        sourceId: source.sourceId,
        sourceVersionId: versionId,
        candidateUrl: candidate,
        canonicalUrl: sourceMetadata['canonical_url'] as String?,
        cachedObjectRef: cachedRef,
        cachedVersionId: cachedVersion,
        cachedCandidateHash:
            presentation['thumbnail_candidate_hash'] as String? ??
                sourceMetadata['thumbnail_candidate_hash'] as String?,
      ),
    );
    if (!resolved.isAvailable ||
        resolved.objectRef == null ||
        resolved.candidateHash == null) {
      return resolved;
    }

    try {
      final stillCurrent = await db.transaction<bool>(() async {
        final current = await getCard(record.card.cardId, loadDocument: false);
        if (current == null) return false;
        final latestVersion = current.currentSourceVersion?.versionId ??
            current.source?.currentVersionId;
        if (latestVersion != versionId) return false;
        final currentPresentation = current.card.presentation;
        final currentSourceMetadata = current.source?.metadata ?? const {};
        final currentCandidate = _firstString([
          currentSourceMetadata['og_image'],
          currentSourceMetadata['thumbnail_url'],
          currentPresentation['thumbnail'],
        ]);
        final currentCandidateHash = SafeThumbnailResolver.candidateHashFor(
          currentCandidate,
          currentSourceMetadata['canonical_url'] as String?,
        );
        if (resolved.candidateHash!.isNotEmpty &&
            currentCandidateHash != resolved.candidateHash) {
          return false;
        }
        final hashIsProjected = resolved.candidateHash!.isEmpty ||
            currentPresentation['thumbnail_candidate_hash'] ==
                resolved.candidateHash;
        if (currentPresentation['thumbnail_ref'] == resolved.objectRef &&
            currentPresentation['thumbnail_version_id'] == versionId &&
            hashIsProjected) {
          return true;
        }
        // This is a rebuildable cache projection, not a user edit. Touch only
        // presentation_json so background work cannot reorder the library or
        // overwrite a concurrent title/body/tag edit with an older record.
        final projectedPresentation = {
          ...currentPresentation,
          'thumbnail_ref': resolved.objectRef,
          'thumbnail_version_id': versionId,
          if (resolved.candidateHash!.isNotEmpty)
            'thumbnail_candidate_hash': resolved.candidateHash,
        };
        await (db.update(
          db.whiteboardCardExtras,
        )..where((t) => t.cardId.equals(record.card.cardId)))
            .write(
          WhiteboardCardExtrasCompanion(
            presentationJson: Value(jsonEncode(projectedPresentation)),
          ),
        );
        return true;
      });
      if (!stillCurrent) return const ResolvedThumbnail.missing();
    } catch (_) {
      // The cache is still a valid rebuildable projection for this process.
      // A later resolve may retry the metadata projection; Card identity and
      // the explicit ingestion commit remain successful either way.
    }
    return resolved;
  }

  /// Resolves an already-cached, integrity-checked thumbnail without making
  /// a network request or mutating Card/Source projections.
  ///
  /// Canvas and card-library render paths use this method so merely bringing
  /// a Card into the viewport can never initiate external I/O. Fetching and
  /// projecting a new thumbnail remains an explicit ingestion/background
  /// concern through [resolveThumbnail].
  Future<ResolvedThumbnail> resolveCachedThumbnail(
    UnifiedCardRecord record,
  ) async {
    final resolver = thumbnailResolver;
    if (resolver == null) {
      return const ResolvedThumbnail.missing();
    }
    final cachedRef = _firstString([
      record.card.presentation['thumbnail_ref'],
      record.source?.metadata['thumbnail_ref'],
    ]);
    if (resolver is SafeThumbnailResolver) {
      final resolved = await resolver.resolveCached(cachedRef);
      return resolved ?? const ResolvedThumbnail.missing();
    }
    return const ResolvedThumbnail.missing();
  }

  Future<List<SourceVersion>> listSourceVersions(String sourceId) async {
    final rows = await (db.select(db.whiteboardSourceVersions)
          ..where((t) => t.sourceId.equals(sourceId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return rows.map(_toVersion).toList();
  }

  /// Loads the immutable object referenced by [version] and reports missing
  /// or corrupt data without turning the object directory into another store.
  Future<SourceObjectRecord> getSourceObject(SourceVersion version) async {
    File file;
    try {
      file = _objectFile(version.objectRef);
    } catch (_) {
      return const SourceObjectRecord(state: SourceObjectState.corrupt);
    }
    final recovered = await RecoverableFileExchange.recover(
      file,
      validator: _isValidJsonMap,
    );
    if (!recovered || !await file.exists()) {
      return const SourceObjectRecord(state: SourceObjectState.missing);
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['source_id'] != version.sourceId ||
          decoded['source_version_id'] != version.versionId) {
        return const SourceObjectRecord(state: SourceObjectState.corrupt);
      }
      return SourceObjectRecord(
        state: SourceObjectState.available,
        payload: decoded,
      );
    } catch (_) {
      return const SourceObjectRecord(state: SourceObjectState.corrupt);
    }
  }

  Future<CardContract?> getCardForSource(String sourceId) =>
      _cardForSource(sourceId);

  /// Atomically writes Source + SourceVersion + Card after user confirmation.
  Future<IngestionCommitResult> commitIngestion(
    IngestionResult result, {
    CardKind cardKind = CardKind.source,
    OwnerSpace ownerSpace = OwnerSpace.user,
    CardCreatedBy createdBy = CardCreatedBy.user,
  }) async {
    if (result.status != IngestionStatus.ok ||
        result.source == null ||
        result.sourceVersion == null) {
      throw StateError('Only successful ingestion results can create cards');
    }
    return _withSourceObjectCommitLock(
      whiteboardRoot.absolute.path,
      () => _commitIngestionLocked(
        result,
        cardKind: cardKind,
        ownerSpace: ownerSpace,
        createdBy: createdBy,
      ),
    );
  }

  Future<IngestionCommitResult> _commitIngestionLocked(
    IngestionResult result, {
    required CardKind cardKind,
    required OwnerSpace ownerSpace,
    required CardCreatedBy createdBy,
  }) async {
    final incomingSource = result.source!;
    final incomingVersion = SourceVersion.fromJson(result.sourceVersion!);
    final existingSource = await _findCanonicalSource(result, incomingSource);
    final sourceId = existingSource?.sourceId ?? incomingSource.sourceId;
    final sameHash = await _versionByHash(
      sourceId,
      incomingVersion.contentHash,
    );
    final version = sameHash ??
        SourceVersion(
          versionId: _versionId(sourceId, incomingVersion.contentHash),
          sourceId: sourceId,
          contentHash: incomingVersion.contentHash,
          objectRef: _sourceObjectRef(sourceId, incomingVersion.contentHash),
          parserVersion: incomingVersion.parserVersion,
          createdAt: incomingVersion.createdAt.toUtc(),
        );
    _SourceObjectWriteGuard? objectWriteGuard;
    File? intentFile;
    late IngestionCommitResult committed;
    try {
      if (sameHash == null) {
        final target = _objectFile(version.objectRef);
        objectWriteGuard = await _SourceObjectWriteGuard.capture(
          target,
          version.objectRef,
        );
        intentFile = _sourceObjectIntentFile(version);
        await _writeSourceObjectIntent(intentFile, version, objectWriteGuard);
        await _writeSourceObject(version, result);
        await _injectFault(
          UnifiedCardRepositoryFaultPoint
              .ingestionAfterObjectWriteBeforeVersionInsert,
        );
      }
      await db.transaction(() async {
        final transactionSource = await _findCanonicalSource(
          result,
          incomingSource,
        );
        final transactionSourceId =
            transactionSource?.sourceId ?? incomingSource.sourceId;
        if (transactionSourceId != sourceId) {
          throw StateError('Canonical Source changed during ingestion');
        }
        final transactionSameHash = await _versionByHash(
          transactionSourceId,
          incomingVersion.contentHash,
        );
        if ((sameHash == null) != (transactionSameHash == null)) {
          throw StateError('SourceVersion changed during ingestion');
        }
        if (sameHash == null) {
          await db.into(db.whiteboardSourceVersions).insert(
                WhiteboardSourceVersionsCompanion.insert(
                  id: version.versionId,
                  sourceId: version.sourceId,
                  contentHash: version.contentHash,
                  objectRef: version.objectRef,
                  parserVersion: Value(version.parserVersion),
                  createdAt: _millis(version.createdAt),
                ),
              );
          await _injectFault(
            UnifiedCardRepositoryFaultPoint.ingestionAfterVersionInsert,
          );
        }
        final now = result.resolvedAt.toUtc();
        final source = SourceContent(
          sourceId: sourceId,
          mediaType: sameHash == null
              ? incomingSource.mediaType
              : (existingSource?.mediaType ?? incomingSource.mediaType),
          title: sameHash == null
              ? incomingSource.title
              : (existingSource?.title ?? incomingSource.title),
          ownerSpace: existingSource?.ownerSpace ?? ownerSpace,
          origin: sameHash == null
              ? incomingSource.origin
              : (existingSource?.origin ?? incomingSource.origin),
          provider: sameHash == null
              ? incomingSource.provider
              : (existingSource?.provider ?? incomingSource.provider),
          canonicalId: sameHash == null
              ? incomingSource.canonicalId
              : existingSource?.canonicalId,
          mimeType: sameHash == null
              ? incomingSource.mimeType
              : (existingSource?.mimeType ?? incomingSource.mimeType),
          currentVersionId: sameHash == null
              ? version.versionId
              : (existingSource?.currentVersionId ?? version.versionId),
          contentHash: sameHash == null
              ? version.contentHash
              : (existingSource?.contentHash ?? version.contentHash),
          objectRef: sameHash == null
              ? version.objectRef
              : (existingSource?.objectRef ?? version.objectRef),
          metadata: {
            ...?existingSource?.metadata,
            ...incomingSource.metadata,
            'canonical_url': sameHash == null
                ? result.canonicalUrl
                : (existingSource?.metadata['canonical_url'] ??
                    result.canonicalUrl),
            if (sameHash == null && result.originalUrl != null)
              'original_url': result.originalUrl,
          },
          createdAt: existingSource?.createdAt ?? incomingSource.createdAt,
          updatedAt: sameHash == null ? now : existingSource?.updatedAt,
          deletedAt: null,
        );
        await _upsertSource(source);

        final existingCard = await _cardForSource(sourceId);
        final thumbnail =
            incomingSource.metadata['og_image'] ?? result.metadata['og_image'];
        final description = incomingSource.metadata['description'] ??
            result.metadata['description'];
        final excerpt = result.metadata['body_excerpt'] as String? ?? '';
        final wasDeleted = existingCard?.deletedAt != null;
        final cardCreated = existingCard == null;
        final nowForCard = result.resolvedAt.toUtc();
        final card = existingCard == null
            ? CardContract(
                cardId: _cardIdForSource(sourceId),
                cardKind: cardKind,
                sourceId: sourceId,
                ownerSpace: ownerSpace,
                title: source.title,
                body: excerpt,
                presentation: {
                  if (thumbnail != null) 'thumbnail': thumbnail,
                  if (description != null) 'description': description,
                },
                createdBy: createdBy,
                createdAt: nowForCard,
                updatedAt: nowForCard,
              )
            : _copyCard(
                existingCard,
                title: source.title.isEmpty ? null : source.title,
                body: sameHash == null && excerpt.isNotEmpty ? excerpt : null,
                presentation: {
                  ...existingCard.presentation,
                  if (thumbnail != null) 'thumbnail': thumbnail,
                  if (description != null) 'description': description,
                },
                deletedAt: null,
                setDeletedAt: true,
                updatedAt: sameHash == null || wasDeleted
                    ? nowForCard
                    : existingCard.updatedAt,
              );
        if (cardCreated) {
          await _insertNewCard(card);
        } else {
          await _updateExistingCard(card);
        }
        committed = IngestionCommitResult(
          source: source,
          version: version,
          versionIsNew: sameHash == null,
          card: card,
          cardCreated: cardCreated,
          cardRestored: wasDeleted,
        );
      });
    } catch (error) {
      if (error is UnifiedCardRepositorySimulatedProcessExit) rethrow;
      await objectWriteGuard?.removeCreatedFilesIfUnreferenced(db);
      if (intentFile != null) await _deleteFileExchange(intentFile);
      rethrow;
    }

    // The Drift transaction above is the commit point. Intent cleanup is
    // deliberately outside the compensation catch: once DB rows reference
    // the new object, cleanup failure must never restore pre-write bytes.
    try {
      await _injectFault(
        UnifiedCardRepositoryFaultPoint
            .ingestionAfterTransactionCommitBeforeIntentCleanup,
      );
      if (intentFile != null) await _deleteFileExchange(intentFile);
    } catch (error) {
      if (error is UnifiedCardRepositorySimulatedProcessExit) rethrow;
      // Startup reconciliation sees the DB reference and removes only intent.
    }
    return committed;
  }

  /// Soft-deletes a Card without deleting Source, versions, rich text, or
  /// BoardItems. Existing placements become honest orphan/deleted references.
  Future<bool> softDeleteCard(String cardId, {DateTime? at}) async {
    final current = await getCard(
      cardId,
      includeDeleted: true,
      loadDocument: false,
    );
    if (current == null || current.card.deletedAt != null) return false;
    final when = (at ?? DateTime.now()).toUtc();
    final updated = _copyCard(
      current.card,
      deletedAt: when,
      setDeletedAt: true,
      updatedAt: when,
    );
    await db.transaction(() => _updateExistingCard(updated));
    return true;
  }

  /// Restores a soft-deleted Card with the same stable id.
  Future<bool> restoreCard(String cardId, {DateTime? at}) async {
    final current = await getCard(
      cardId,
      includeDeleted: true,
      loadDocument: false,
    );
    if (current == null || current.card.deletedAt == null) return false;
    final updated = _copyCard(
      current.card,
      deletedAt: null,
      setDeletedAt: true,
      updatedAt: (at ?? DateTime.now()).toUtc(),
    );
    await db.transaction(() => _updateExistingCard(updated));
    return true;
  }

  /// Whether a card has at least one placement (optionally on one board).
  Future<bool> isCardPlaced(String cardId, {String? boardId}) async {
    final query = db.select(db.whiteboardBoardItems)
      ..where((t) => t.cardId.equals(cardId));
    if (boardId != null) query.where((t) => t.boardId.equals(boardId));
    query.limit(1);
    return await query.getSingleOrNull() != null;
  }

  // Migration-only API -----------------------------------------------------

  /// Imports a legacy Card without overwriting a newer production row.
  Future<bool> importLegacyCard(CardContract legacy) async {
    final current = await getCard(
      legacy.cardId,
      includeDeleted: true,
      loadDocument: false,
    );
    if (current == null) {
      await db.transaction(() => _insertNewCard(legacy));
      return true;
    }
    final currentTime = current.card.updatedAt ?? current.card.createdAt;
    final legacyTime = legacy.updatedAt ?? legacy.createdAt;
    if (!legacyTime.isAfter(currentTime)) return false;
    await db.transaction(() => _updateExistingCard(legacy));
    return true;
  }

  /// Adds the missing Extras half for a legacy Drift note without changing
  /// its MemoryCards row.
  Future<bool> backfillLegacyMemoryCardExtra(String cardId) async {
    final row = await (db.select(
      db.memoryCards,
    )..where((t) => t.id.equals(cardId)))
        .getSingleOrNull();
    if (row == null) return false;
    final existing = await (db.select(
      db.whiteboardCardExtras,
    )..where((t) => t.cardId.equals(cardId)))
        .getSingleOrNull();
    if (existing != null) return false;
    await db.into(db.whiteboardCardExtras).insert(
          WhiteboardCardExtrasCompanion.insert(
            cardId: cardId,
            cardKind: CardKind.note.name,
            body: Value(row.retrievalText),
            updatedAt: Value(row.updatedAt),
          ),
        );
    return true;
  }

  /// Imports a legacy Source / version set and optional confirmed Card.
  Future<void> importLegacyIngestion({
    required SourceContent source,
    required List<SourceVersion> versions,
    CardContract? card,
  }) async {
    await db.transaction(() async {
      final existing = await _sourceById(source.sourceId);
      for (final version in versions) {
        if (await _versionByHash(source.sourceId, version.contentHash) !=
            null) {
          continue;
        }
        await db.into(db.whiteboardSourceVersions).insert(
              WhiteboardSourceVersionsCompanion.insert(
                id: version.versionId,
                sourceId: version.sourceId,
                contentHash: version.contentHash,
                objectRef: version.objectRef,
                parserVersion: Value(version.parserVersion),
                createdAt: _millis(version.createdAt),
              ),
            );
      }
      final existingTime = existing?.updatedAt ?? existing?.createdAt;
      final legacyTime = source.updatedAt ?? source.createdAt;
      if (existing == null || legacyTime.isAfter(existingTime!)) {
        await _upsertSource(source);
      }
      if (card != null) {
        final currentCard = await getCard(
          card.cardId,
          includeDeleted: true,
          loadDocument: false,
        );
        if (currentCard == null) {
          await _insertNewCard(card);
        } else {
          final currentTime =
              currentCard.card.updatedAt ?? currentCard.card.createdAt;
          final legacyCardTime = card.updatedAt ?? card.createdAt;
          if (legacyCardTime.isAfter(currentTime)) {
            await _updateExistingCard(card);
          }
        }
      }
    });
  }

  // Internal mapping / persistence ----------------------------------------

  Future<void> _insertNewCard(CardContract card) async {
    await _insertMemoryCardRow(card);
    await _insertCardExtraRow(card);
  }

  Future<void> _insertMemoryCardRow(CardContract card) async {
    await db.into(db.memoryCards).insert(
          MemoryCardsCompanion.insert(
            id: card.cardId,
            memoryScope: const Value('user_truth'),
            type: 'note',
            title: card.title,
            dropletLabel: _dropletLabel(card.title),
            presentationModule: '[]',
            retrievalText: card.body,
            valence: 0,
            arousal: 0,
            createdAt: _millis(card.createdAt),
            updatedAt: _millis(card.updatedAt ?? card.createdAt),
          ),
        );
  }

  Future<void> _insertCardExtraRow(CardContract card) async {
    await db.into(db.whiteboardCardExtras).insert(
          WhiteboardCardExtrasCompanion.insert(
            cardId: card.cardId,
            cardKind: card.cardKind.name,
            sourceId: Value(card.sourceId),
            ownerSpace: Value(card.ownerSpace.name),
            body: Value(card.body),
            tagsJson: Value(jsonEncode(card.tags)),
            presentationJson: Value(
              card.presentation.isEmpty ? null : jsonEncode(card.presentation),
            ),
            createdBy: Value(card.createdBy.name),
            updatedAt: Value(
              card.updatedAt == null ? null : _millis(card.updatedAt!),
            ),
            deletedAt: Value(
              card.deletedAt == null ? null : _millis(card.deletedAt!),
            ),
          ),
        );
  }

  Future<void> _injectFault(UnifiedCardRepositoryFaultPoint point) async {
    await faultInjector?.call(point);
  }

  Future<T> _withSourceObjectCommitLock<T>(
    String key,
    Future<T> Function() action,
  ) async {
    final previous = _sourceObjectCommitLocks[key] ?? Future<void>.value();
    final gate = Completer<void>();
    final current = gate.future;
    _sourceObjectCommitLocks[key] = current;
    try {
      await previous.catchError((_) {});
      return await action();
    } finally {
      gate.complete();
      if (identical(_sourceObjectCommitLocks[key], current)) {
        _sourceObjectCommitLocks.remove(key);
      }
    }
  }

  Future<void> _updateExistingCard(CardContract card) async {
    await (db.update(
      db.memoryCards,
    )..where((t) => t.id.equals(card.cardId)))
        .write(
      MemoryCardsCompanion(
        title: Value(card.title),
        dropletLabel: Value(_dropletLabel(card.title)),
        retrievalText: Value(card.body),
        updatedAt: Value(_millis(card.updatedAt ?? card.createdAt)),
      ),
    );
    await db.into(db.whiteboardCardExtras).insertOnConflictUpdate(
          WhiteboardCardExtrasCompanion.insert(
            cardId: card.cardId,
            cardKind: card.cardKind.name,
            sourceId: Value(card.sourceId),
            ownerSpace: Value(card.ownerSpace.name),
            body: Value(card.body),
            tagsJson: Value(jsonEncode(card.tags)),
            presentationJson: Value(
              card.presentation.isEmpty ? null : jsonEncode(card.presentation),
            ),
            createdBy: Value(card.createdBy.name),
            updatedAt: Value(
              card.updatedAt == null ? null : _millis(card.updatedAt!),
            ),
            deletedAt: Value(
              card.deletedAt == null ? null : _millis(card.deletedAt!),
            ),
          ),
        );
  }

  Future<void> _upsertSource(SourceContent source) async {
    await db.into(db.whiteboardSources).insertOnConflictUpdate(
          WhiteboardSourcesCompanion.insert(
            id: source.sourceId,
            mediaType: source.mediaType.name,
            title: source.title,
            ownerSpace: Value(source.ownerSpace.name),
            origin: Value(source.origin.name),
            provider: Value(source.provider),
            canonicalId: Value(source.canonicalId),
            mimeType: Value(source.mimeType),
            currentVersionId: Value(source.currentVersionId),
            contentHash: Value(source.contentHash),
            objectRef: Value(source.objectRef),
            metadataJson: Value(
              source.metadata.isEmpty ? null : jsonEncode(source.metadata),
            ),
            createdAt: _millis(source.createdAt),
            updatedAt: Value(
              source.updatedAt == null ? null : _millis(source.updatedAt!),
            ),
            deletedAt: Value(
              source.deletedAt == null ? null : _millis(source.deletedAt!),
            ),
          ),
        );
  }

  Future<CardContract?> _cardForSource(String sourceId) async {
    final extra = await (db.select(db.whiteboardCardExtras)
          ..where((t) => t.sourceId.equals(sourceId))
          ..limit(1))
        .getSingleOrNull();
    if (extra == null) return null;
    final row = await (db.select(
      db.memoryCards,
    )..where((t) => t.id.equals(extra.cardId)))
        .getSingleOrNull();
    return row == null ? null : _toCard(row, extra);
  }

  Future<SourceContent?> _sourceById(String sourceId) async {
    final row = await (db.select(
      db.whiteboardSources,
    )..where((t) => t.id.equals(sourceId)))
        .getSingleOrNull();
    return row == null ? null : _toSource(row);
  }

  Future<SourceVersion?> _versionById(String versionId) async {
    final row = await (db.select(
      db.whiteboardSourceVersions,
    )..where((t) => t.id.equals(versionId)))
        .getSingleOrNull();
    return row == null ? null : _toVersion(row);
  }

  Future<SourceVersion?> _versionByHash(
    String sourceId,
    String contentHash,
  ) async {
    final row = await (db.select(db.whiteboardSourceVersions)
          ..where(
            (t) =>
                t.sourceId.equals(sourceId) & t.contentHash.equals(contentHash),
          )
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _toVersion(row);
  }

  Future<SourceContent?> _findCanonicalSource(
    IngestionResult result,
    SourceContent incoming,
  ) async {
    final rows = await db.select(db.whiteboardSources).get();
    rows.sort((left, right) => left.id.compareTo(right.id));
    for (final row in rows) {
      if (incoming.canonicalId != null &&
          row.provider == incoming.provider &&
          row.canonicalId == incoming.canonicalId) {
        return _toSource(row);
      }
      final metadata = _decodeMap(row.metadataJson);
      if (row.provider == incoming.provider &&
          metadata?['canonical_url'] == result.canonicalUrl) {
        return _toSource(row);
      }
    }
    return _sourceById(incoming.sourceId);
  }

  Future<void> _writeSourceObject(
    SourceVersion version,
    IngestionResult result,
  ) async {
    final file = _objectFile(version.objectRef);
    await file.parent.create(recursive: true);
    final payload = <String, dynamic>{
      'schema_version': 1,
      'source_id': version.sourceId,
      'source_version_id': version.versionId,
      'canonical_url': result.canonicalUrl,
      if (result.originalUrl != null) 'original_url': result.originalUrl,
      if (result.metadata['body_text'] is String)
        'body_text': result.metadata['body_text'],
      'metadata': {
        for (final entry in result.metadata.entries)
          if (entry.key != 'body_text') entry.key: entry.value,
      },
    };
    await _injectFault(
      UnifiedCardRepositoryFaultPoint.ingestionDuringObjectExchange,
    );
    await RecoverableFileExchange.write(
      file,
      jsonEncode(payload),
      validator: _isValidJsonMap,
    );
  }

  Directory get _sourceObjectIntentRoot => Directory(
        _join(_join(whiteboardRoot.path, 'objects'), 'source_object_intents'),
      );

  Directory get _sourceObjectRoot => Directory(
        _join(_join(whiteboardRoot.path, 'objects'), 'sources'),
      );

  File _sourceObjectIntentFile(SourceVersion version) {
    final name =
        base64Url.encode(utf8.encode(version.objectRef)).replaceAll('=', '');
    return File(_join(_sourceObjectIntentRoot.path, '$name.json'));
  }

  Future<void> _writeSourceObjectIntent(
    File file,
    SourceVersion version,
    _SourceObjectWriteGuard guard,
  ) async {
    await file.parent.create(recursive: true);
    await RecoverableFileExchange.write(
      file,
      jsonEncode({
        'schema_version': 2,
        'kind': 'source_object_commit',
        'object_ref': version.objectRef,
        'source_id': version.sourceId,
        'source_version_id': version.versionId,
        'pre_write_snapshot': guard.intentSnapshot,
      }),
      validator: _isValidSourceObjectIntentJson,
    );
  }

  Future<String?> _readBoundedIntentCandidate(File file) async {
    try {
      final beforeLength = await file.length();
      if (beforeLength > _maxSourceObjectIntentBytes) return null;
      final reader = await file.open();
      try {
        final bytes = await reader.read(_maxSourceObjectIntentBytes + 1);
        if (bytes.length > _maxSourceObjectIntentBytes ||
            await file.length() != bytes.length) {
          return null;
        }
        return utf8.decode(bytes, allowMalformed: false);
      } finally {
        await reader.close();
      }
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isSafeContainedSourceObjectFile(File target) async {
    final sourceRoot = _sourceObjectRoot;
    if (!await _isDirectoryContained(
      root: whiteboardRoot,
      child: sourceRoot,
    )) {
      return false;
    }
    if (!await _isDirectoryContained(
      root: sourceRoot,
      child: target.parent,
    )) {
      return false;
    }
    for (final candidate in <File>[
      target,
      RecoverableFileExchange.tempFor(target),
      RecoverableFileExchange.backupFor(target),
    ]) {
      final type = await FileSystemEntity.type(
        candidate.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.notFound) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _isDirectoryContained({
    required Directory root,
    required Directory child,
  }) async {
    try {
      final rootType = await FileSystemEntity.type(
        root.path,
        followLinks: false,
      );
      final childType = await FileSystemEntity.type(
        child.path,
        followLinks: false,
      );
      if (rootType != FileSystemEntityType.directory ||
          childType != FileSystemEntityType.directory) {
        return false;
      }
      final rootPath = path_api.normalize(
        path_api.absolute(await _canonicalizeDirectory(root.path)),
      );
      final childPath = path_api.normalize(
        path_api.absolute(await _canonicalizeDirectory(child.path)),
      );
      return path_api.isWithin(rootPath, childPath);
    } catch (_) {
      return false;
    }
  }

  Future<String> _canonicalizeDirectory(String path) =>
      sourceObjectPathCanonicalizer?.call(path) ??
      Directory(path).resolveSymbolicLinks();

  static Future<void> _deleteFileExchange(File file) async {
    for (final candidate in <File>[
      file,
      RecoverableFileExchange.tempFor(file),
      RecoverableFileExchange.backupFor(file),
    ]) {
      if (await candidate.exists()) await candidate.delete();
    }
  }

  File _objectFile(String objectRef) {
    if (objectRef.contains('..') ||
        objectRef.contains('\\') ||
        objectRef.startsWith('/') ||
        objectRef.contains(':') ||
        !objectRef.startsWith('objects/')) {
      throw StateError('Unsafe object_ref: $objectRef');
    }
    return File(_join(whiteboardRoot.path, objectRef));
  }

  static bool _isValidJsonMap(String contents) {
    try {
      return jsonDecode(contents) is Map<String, dynamic>;
    } catch (_) {
      return false;
    }
  }

  static bool _isValidSourceObjectIntentJson(String contents) {
    try {
      final decoded = jsonDecode(contents);
      return decoded is Map<String, dynamic> &&
          _isValidSourceObjectIntentMap(decoded);
    } catch (_) {
      return false;
    }
  }

  static bool _isValidSourceObjectIntentMap(Map<String, dynamic> intent) {
    const keys = {
      'schema_version',
      'kind',
      'object_ref',
      'source_id',
      'source_version_id',
      'pre_write_snapshot',
    };
    if (intent.length != keys.length ||
        !intent.keys.every(keys.contains) ||
        intent['schema_version'] != 2 ||
        intent['kind'] != 'source_object_commit') {
      return false;
    }
    final objectRef = _safeSourceObjectIntentRef(intent);
    if (objectRef == null) return false;
    return _SourceObjectWriteGuard.fromIntent(
          File('intent-validation.json'),
          objectRef,
          intent['pre_write_snapshot'],
        ) !=
        null;
  }

  static String? _safeSourceObjectIntentRef(Map<String, dynamic> intent) {
    final objectRef = _safeManagedSourceObjectRef(intent['object_ref']);
    final sourceId = intent['source_id'];
    final sourceVersionId = intent['source_version_id'];
    if (objectRef == null ||
        sourceId is! String ||
        sourceVersionId is! String ||
        sourceId.isEmpty ||
        sourceVersionId.isEmpty ||
        objectRef != 'objects/sources/$sourceId/$sourceVersionId.json') {
      return null;
    }
    return objectRef;
  }

  static String? _safeManagedSourceObjectRef(Object? raw) {
    if (raw is! String ||
        raw.contains('..') ||
        raw.contains('\\') ||
        raw.contains(':')) {
      return null;
    }
    final segments = raw.split('/');
    if (segments.length != 4 ||
        segments[0] != 'objects' ||
        segments[1] != 'sources' ||
        segments[2].isEmpty ||
        segments[3].isEmpty ||
        !segments[3].endsWith('.json')) {
      return null;
    }
    return raw;
  }

  static CardContract _toCard(MemoryCard row, WhiteboardCardExtra extra) =>
      CardContract(
        cardId: row.id,
        cardKind: CardKind.fromString(extra.cardKind),
        sourceId: extra.sourceId,
        ownerSpace: OwnerSpace.fromString(extra.ownerSpace),
        title: row.title,
        body: row.retrievalText,
        tags: _decodeStringList(extra.tagsJson),
        presentation: _decodeMap(extra.presentationJson) ?? const {},
        createdBy: CardCreatedBy.fromString(extra.createdBy),
        createdAt: _date(row.createdAt),
        updatedAt: extra.updatedAt == null ? null : _date(extra.updatedAt!),
        deletedAt: extra.deletedAt == null ? null : _date(extra.deletedAt!),
      );

  static SourceContent _toSource(WhiteboardSource row) => SourceContent(
        sourceId: row.id,
        mediaType: SourceMediaType.fromString(row.mediaType),
        title: row.title,
        ownerSpace: OwnerSpace.fromString(row.ownerSpace),
        origin: SourceOrigin.fromString(row.origin),
        provider: row.provider,
        canonicalId: row.canonicalId,
        mimeType: row.mimeType,
        currentVersionId: row.currentVersionId,
        contentHash: row.contentHash,
        objectRef: row.objectRef,
        metadata: _decodeMap(row.metadataJson) ?? const {},
        createdAt: _date(row.createdAt),
        updatedAt: row.updatedAt == null ? null : _date(row.updatedAt!),
        deletedAt: row.deletedAt == null ? null : _date(row.deletedAt!),
      );

  static SourceVersion _toVersion(WhiteboardSourceVersion row) => SourceVersion(
        versionId: row.id,
        sourceId: row.sourceId,
        contentHash: row.contentHash,
        objectRef: row.objectRef,
        parserVersion: row.parserVersion,
        createdAt: _date(row.createdAt),
      );

  static CardContract _copyCard(
    CardContract card, {
    CardKind? cardKind,
    String? sourceId,
    bool setSourceId = false,
    String? title,
    String? body,
    List<String>? tags,
    Map<String, dynamic>? presentation,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool setDeletedAt = false,
  }) =>
      CardContract(
        cardId: card.cardId,
        cardKind: cardKind ?? card.cardKind,
        sourceId: setSourceId ? sourceId : card.sourceId,
        ownerSpace: card.ownerSpace,
        title: title ?? card.title,
        body: body ?? card.body,
        tags: tags ?? card.tags,
        presentation: presentation ?? card.presentation,
        createdBy: card.createdBy,
        createdAt: card.createdAt,
        updatedAt: updatedAt ?? card.updatedAt,
        deletedAt: setDeletedAt ? deletedAt : card.deletedAt,
      );

  static CardDocumentState _documentState(RichTextLoadStatus? status) {
    switch (status) {
      case RichTextLoadStatus.available:
        return CardDocumentState.available;
      case RichTextLoadStatus.corrupt:
        return CardDocumentState.corrupt;
      case RichTextLoadStatus.missing:
      case null:
        return CardDocumentState.missing;
    }
  }

  static Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static List<String> _decodeStringList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.whereType<String>().toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  static List<String> _normalizeTags(List<String> tags) {
    final result = <String>[];
    final seen = <String>{};
    for (final tag in tags) {
      final trimmed = tag.trim();
      if (trimmed.isEmpty || !seen.add(trimmed.toLowerCase())) continue;
      result.add(trimmed);
    }
    return result;
  }

  static String _firstNonEmptyLine(String text, {required String fallback}) {
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return fallback;
  }

  static String? _firstString(List<Object?> values) {
    for (final value in values) {
      if (value is! String) continue;
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  static String _dropletLabel(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return '卡片';
    return trimmed.length <= 4 ? trimmed : trimmed.substring(0, 4);
  }

  static String _cardIdForSource(String sourceId) =>
      'card_${sourceId.replaceFirst(RegExp(r'^src_'), '')}';

  static String _versionId(String sourceId, String hash) =>
      '${sourceId.replaceFirst(RegExp(r'^src_'), 'ver_')}_$hash';

  static String _sourceObjectRef(String sourceId, String hash) =>
      'objects/sources/$sourceId/${_versionId(sourceId, hash)}.json';

  static int _millis(DateTime value) => value.toUtc().millisecondsSinceEpoch;

  static DateTime _date(int value) =>
      DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

  static String _join(String a, String b) =>
      '$a${Platform.pathSeparator}${b.replaceAll('/', Platform.pathSeparator)}';
}
