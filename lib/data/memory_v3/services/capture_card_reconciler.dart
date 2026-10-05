part of 'record_organizer_service.dart';

String captureIssueMessage(String reason, {bool deleted = false}) {
  final source = deleted ? '来源已删除' : '来源已更新';
  return switch (reason) {
    'user_modified' => '$source，已保留你修改过的卡片。',
    'output_changed' => '$source，卡片生成后另有变动，已保留并等待确认。',
    'output_missing' => '$source，原卡片已不存在，未自动重新创建。',
    'source_ownership_unverified' => '$source，无法确认卡片的独占来源，已保留并等待确认。',
    'legacy_generation_unverified' => '$source，旧处理记录缺少生成基线，已保留原卡片并等待确认。',
    _ => '无法确认新旧卡片的对应关系，已保留原卡片，等待确认。',
  };
}

/// Capture-only persistence. No dedupe against unrelated cards, finance bridge,
/// background jobs or user-actor impersonation. The caller's real DB transaction
/// also contains the capture ledger and acknowledgement.
extension CaptureCardReconciler on RecordOrganizerServiceV3 {
  bool captureUsesDatabase(AppDatabase db) => identical(_db, db);

  static String _digest(Object? value) {
    Object? sorted(Object? v) {
      if (v is Map) {
        final keys = v.keys.cast<String>().toList()..sort();
        return {for (final k in keys) k: sorted(v[k])};
      }
      if (v is List) return v.map(sorted).toList();
      return v;
    }

    return sha256.convert(utf8.encode(jsonEncode(sorted(value)))).toString();
  }

  static Map<String, dynamic> _identity(OrganizedCard c) => {
        'content': _digest(c.toJson()),
        'identity': _digest([c.type, c.structuredFieldsType, c.title.trim()]),
      };

  Future<String?> _captureFingerprint(String id) async {
    final card = await (_db.select(_db.memoryCards)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (card == null) return null;
    final sources = await (_db.select(_db.memoryCardSources)
          ..where((t) => t.cardId.equals(id)))
        .get();
    final fields = await (_db.select(_db.memoryCardStructuredFields)
          ..where((t) => t.cardId.equals(id)))
        .get();
    final links = await (_db.select(_db.memoryEntityLinks)
          ..where((t) =>
              t.sourceTable.equals('memory_cards') & t.sourceId.equals(id)))
        .get();
    final relations = await (_db.select(_db.memoryCardRelations)
          ..where((t) => t.fromCardId.equals(id) | t.toCardId.equals(id)))
        .get();
    final assets = await (_db.select(_db.memoryCardAssets)
          ..where((t) => t.cardId.equals(id)))
        .get();
    List<String> rows(Iterable<Object?> values) =>
        values.map(_digest).toList()..sort();
    return _digest({
      'card': card.toJson(),
      'sources': rows(sources.map((r) => r.toJson())),
      'fields': rows(fields.map((r) => r.toJson())),
      'links': rows(links.map((r) => r.toJson())),
      'relations': rows(relations.map((r) => r.toJson())),
      'assets': rows(assets.map((r) => r.toJson())),
    });
  }

  Future<String?> _captureProtection(
      Map<String, dynamic> slot, String sourceRef) async {
    final id = slot['id'] as String;
    final fingerprint = await _captureFingerprint(id);
    if (fingerprint == null) return 'output_missing';
    final corrections = await (_db.select(_db.userCorrections)
          ..where((t) => t.targetId.equals(id)))
        .get();
    final fields = await (_db.select(_db.memoryCardStructuredFields)
          ..where((t) => t.cardId.equals(id)))
        .getSingleOrNull();
    final relations = await (_db.select(_db.memoryCardRelations)
          ..where((t) =>
              (t.fromCardId.equals(id) | t.toCardId.equals(id)) &
              t.userCorrected.equals(true)))
        .get();
    if (corrections.isNotEmpty ||
        fields?.userCorrected == true ||
        relations.isNotEmpty) {
      return 'user_modified';
    }
    final sources = await (_db.select(_db.memoryCardSources)
          ..where((t) => t.cardId.equals(id)))
        .get();
    if (sources.length != 1 || sources.single.sourceRef != sourceRef) {
      return 'source_ownership_unverified';
    }
    if (slot['snapshot'] == null) return 'legacy_generation_unverified';
    if (fingerprint != slot['snapshot']) return 'output_changed';
    return null;
  }

  /// Old receipts have IDs but no trustworthy generated baseline. Import their
  /// mapping without inventing a baseline from today's possibly edited cards.
  Future<List<Map<String, dynamic>>> captureLegacySlots(
          List<String> ids) async =>
      [
        for (final id in ids.toSet()) {'id': id, 'legacy': true}
      ];

  Future<void> _removeCaptureProjection(String id) async {
    await (_db.delete(_db.memoryCardSources)..where((t) => t.cardId.equals(id)))
        .go();
    await (_db.delete(_db.memoryCardStructuredFields)
          ..where((t) => t.cardId.equals(id)))
        .go();
    await (_db.delete(_db.memoryEntityLinks)
          ..where((t) =>
              t.sourceTable.equals('memory_cards') & t.sourceId.equals(id)))
        .go();
    await (_db.delete(_db.memoryCardRelations)
          ..where((t) => t.fromCardId.equals(id) | t.toCardId.equals(id)))
        .go();
    await (_db.delete(_db.memoryCardAssets)..where((t) => t.cardId.equals(id)))
        .go();
    await (_db.delete(_db.memoryCards)..where((t) => t.id.equals(id))).go();
    await (_db.delete(_db.memoryEmbeddings)
          ..where((t) =>
              t.targetTable.equals('memory_cards') & t.targetId.equals(id)))
        .go();
    // Unlike the general best-effort UI path, capture reconciliation requires
    // the search projection to commit or roll back with the source lifecycle.
    await _db.searchDao.deleteMemoryV3Fts(id);
  }

  Future<Map<String, dynamic>> _writeCaptureCard(
      OrganizedCard card, RecordSource source,
      {String? existingId}) async {
    final id = existingId ?? RecordOrganizerServiceV3._uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final previous = await (_db.select(_db.memoryCards)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    final previousLinks = await (_db.select(_db.memoryEntityLinks)
          ..where((t) =>
              t.sourceTable.equals('memory_cards') & t.sourceId.equals(id)))
        .get();
    if (previous != null) await _removeCaptureProjection(id);
    await _db.into(_db.memoryCards).insert(MemoryCardsCompanion.insert(
          id: id,
          memoryScope: const Value('user_truth'),
          type: card.type,
          title: card.title,
          dropletLabel: card.dropletLabel,
          presentationModule: jsonEncode(card.presentationModule),
          retrievalText: card.retrievalText,
          valence: card.valence,
          arousal: card.arousal,
          status: Value(card.status),
          needsFollowUp: Value(card.needsFollowUp == null
              ? null
              : jsonEncode(card.needsFollowUp)),
          createdAt: previous?.createdAt ?? now,
          updatedAt: now,
        ));
    await _db
        .into(_db.memoryCardSources)
        .insert(MemoryCardSourcesCompanion.insert(
          cardId: id,
          rawInput: source.rawInput,
          recordedAt: source.recordedAt.millisecondsSinceEpoch,
          sourceRef: Value(source.sourceRef),
          sourceKind: 'import',
        ));
    if (card.structuredFields != null && card.structuredFieldsType != null) {
      await _db
          .into(_db.memoryCardStructuredFields)
          .insert(MemoryCardStructuredFieldsCompanion.insert(
            cardId: id,
            structuredFieldsType: card.structuredFieldsType!,
            fieldsJson: jsonEncode(card.structuredFields),
            generatedByVersion: const Value('capture_reconcile.v1'),
            createdAt: now,
            updatedAt: now,
          ));
    }
    for (final link in card.entityLinks) {
      final existingEntity = await (_db.select(_db.memoryEntities)
            ..where((t) =>
                t.name.lower().equals(link.name.toLowerCase()) &
                t.status.isNotIn(const ['deleted', 'merged'])))
          .getSingleOrNull();
      final entityId = existingEntity != null &&
              previousLinks.any((l) => l.entityId == existingEntity.id)
          ? existingEntity.id
          : await _resolveEntity(link, now: now);
      await _db
          .into(_db.memoryEntityLinks)
          .insert(MemoryEntityLinksCompanion.insert(
            id: RecordOrganizerServiceV3._uuid.v4(),
            sourceTable: 'memory_cards',
            sourceId: id,
            entityId: entityId,
            relation: link.relation,
            confidence: Value(link.confidence),
            createdAt: now,
          ));
    }
    await _captureAudit(
        id, previous == null ? 'create' : 'update', source.sourceRef!);
    await _db.searchDao.upsertMemoryV3Fts(
        cardId: id,
        dropletLabel: card.dropletLabel,
        title: card.title,
        retrievalText: card.retrievalText);
    return {
      'id': id,
      ..._identity(card),
      'snapshot': await _captureFingerprint(id)
    };
  }

  Future<void> _captureAudit(String id, String operation, String sourceRef) =>
      _db
          .into(_db.memoryCardOperations)
          .insert(MemoryCardOperationsCompanion.insert(
            id: RecordOrganizerServiceV3._uuid.v4(), cardId: id,
            operationType: operation,
            // No raw capture text or discarded generation in the processing log.
            payload: jsonEncode({
              '_actor': 'import',
              'sourceRef': sourceRef,
              'processor': 'capture_reconcile.v1'
            }),
            sourceKind: 'capture_reconcile',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ))
          .then((_) {});

  /// Result includes only current ownership IDs, baseline digests and explicit
  /// actionable issues; it never duplicates source text into the durable ledger.
  Future<Map<String, dynamic>> reconcileCapture({
    required List<Map<String, dynamic>> previous,
    required OrganizedRecord organized,
    required RecordSource source,
    bool deleted = false,
  }) =>
      _db.transaction(() async {
        if (source.sourceKind != 'import' ||
            !(source.sourceRef?.startsWith('captures:') ?? false)) {
          throw ArgumentError('capture source required');
        }
        final cards = organized.cards
            .where((c) => !const ['task', 'schedule', 'plan'].contains(c.type))
            .toList();
        final old = previous.map((s) => Map<String, dynamic>.from(s)).toList();
        final unmatched = cards.toList();
        final pairs = <int, OrganizedCard>{};
        // Equal-content multiplicities are interchangeable, unlike merely equal
        // titles. Preserve every existing ID for equal-sized identical groups.
        for (final digest
            in old.map((s) => s['content']).whereType<String>().toSet()) {
          final indices = old
              .asMap()
              .entries
              .where((e) => e.value['content'] == digest)
              .map((e) => e.key)
              .toList();
          final candidates = unmatched
              .where((c) => _identity(c)['content'] == digest)
              .toList();
          if (indices.length == candidates.length) {
            for (var n = 0; n < indices.length; n++) {
              pairs[indices[n]] = candidates[n];
              unmatched.remove(candidates[n]);
            }
          }
        }
        // Ordering is never identity. Match only unique generated content first,
        // then unique title/type identity. Single-card captures keep their sole ID
        // even when a corrected input legitimately changes its type/classification.
        for (final field in ['content', 'identity']) {
          for (var i = 0; i < old.length; i++) {
            if (pairs.containsKey(i) || old[i][field] == null) continue;
            final candidates = unmatched
                .where((c) => _identity(c)[field] == old[i][field])
                .toList();
            final peers = old.asMap().entries.where((e) =>
                !pairs.containsKey(e.key) && e.value[field] == old[i][field]);
            if (candidates.length == 1 && peers.length == 1) {
              pairs[i] = candidates.single;
              unmatched.remove(candidates.single);
            }
          }
        }
        if (!deleted && old.length == 1 && cards.length == 1 && pairs.isEmpty) {
          pairs[0] = cards.single;
          unmatched.clear();
        }
        final ambiguous =
            !deleted && unmatched.isNotEmpty && pairs.length < old.length;
        final slots = <Map<String, dynamic>>[];
        final issues = <Map<String, dynamic>>[];
        final removed = <String>[];
        for (var i = 0; i < old.length; i++) {
          final slot = old[i], id = slot['id'] as String;
          final protection = await _captureProtection(slot, source.sourceRef!);
          if (protection != null) {
            // Missing cards may have been explicitly deleted by the user. Keep an
            // ID-only marker so a later generation cannot recreate them silently.
            slots.add(deleted || protection == 'output_missing'
                ? {
                    'id': id,
                    if (protection == 'output_missing') 'missing': true
                  }
                : slot);
            issues.add({
              'card_id': id,
              'reason': protection,
              'message': captureIssueMessage(protection, deleted: deleted)
            });
            continue;
          }
          if (ambiguous && !pairs.containsKey(i)) {
            slots.add(slot);
            continue;
          }
          final replacement = pairs[i];
          if (!deleted && replacement != null) {
            slots.add(
                await _writeCaptureCard(replacement, source, existingId: id));
          } else {
            await _removeCaptureProjection(id);
            await _captureAudit(id, 'delete', source.sourceRef!);
            removed.add(id);
          }
        }
        if (ambiguous) {
          issues.add({
            'reason': 'output_identity_ambiguous',
            'message': captureIssueMessage('output_identity_ambiguous')
          });
        } else if (!deleted) {
          for (final card in unmatched) {
            slots.add(await _writeCaptureCard(card, source));
          }
        }
        return {'slots': slots, 'issues': issues, 'removed_ids': removed};
      });
}
