/// V3 Record Organizer service.
///
/// Persists [OrganizedRecord] outputs across the Memory V3 table family.
/// Implements V3 § 9 — single explicit-write path for User-truth Memory Cards.
///
/// Boundary:
/// - Does NOT contain the LLM prompt or call. That lives in
///   [RecordOrganizerAgent] / [organizeRawInputV3]. Pass it the
///   pre-organized [OrganizedRecord].
/// - Does NOT auto-capture. Only called from explicit user write paths.
/// - All writes go through [memory_card_operations] as audit log; the I-facing
///   query layer reads only the projection tables.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/drift.dart';
import 'package:memex/data/services/ai_finance_service.dart';
import 'package:memex/data/services/proactive_outing_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';
import 'package:uuid/uuid.dart';

import '../agents/record_organizer_agent/agent.dart';
import '../models/organized_record.dart';
import 'life_insight_scheduler.dart';
import 'user_rhythm_service.dart';

final _logger = getLogger('memory_v3.RecordOrganizerService');

/// Field names inside `structuredFields` that represent time anchors for the
/// recorded event. These are intentionally NEVER writable through the
/// companion-facing `memory_v3_update_card` tool's `structured_fields`
/// parameter — the LLM can only change them via the explicit `time_overrides`
/// parameter, and only when the user says the event time is wrong. This stops
/// accidental time drift when the LLM regenerates a card's business fields.
const Set<String> _timeFieldNames = {
  'occurredAt',
  'occurredEndAt',
  'nextActionAt',
  'dueAt',
  'startAt',
  'endAt',
  'remindAt',
  'paidAt',
  'receivedAt',
  'sleepStart',
  'sleepEnd',
  'wakeDate',
};

/// When the caller updates `retrievalText` without explicitly passing a new
/// `presentationModule`, we try to keep the visible summary card in sync by
/// rewriting the text inside text blocks. Non-text blocks are preserved so
/// number/quote/table/media layouts stay intact.
///
/// Returns the updated JSON-decoded PresentationModule map, or null if there
/// is nothing to change (e.g. no existing blocks, or no text blocks).
Map<String, dynamic>? _syncRetrievalTextIntoBlocks(
  String existingJson,
  String newRetrievalText,
) {
  final parsed = _safeParseJson(existingJson);
  if (parsed is! Map) return null;
  final existing = Map<String, dynamic>.from(parsed);
  final rawBlocks = existing['blocks'];
  if (rawBlocks is! List || rawBlocks.isEmpty) return null;
  final hasTextBlock = rawBlocks.any(
    (b) => b is Map && (b['type'] ?? b['kind']) == 'text',
  );
  if (!hasTextBlock) return null;

  // Split retrievalText into sentences by Chinese/English punctuation.
  // We keep block order: each existing text block gets the next sentence,
  // and any leftover sentences get appended as new text blocks at the end.
  final sentences = _splitIntoSentences(newRetrievalText);
  if (sentences.isEmpty) return null;

  final newBlocks = <Map<String, dynamic>>[];
  var nextSentenceIdx = 0;
  for (final block in rawBlocks) {
    if (block is! Map) {
      newBlocks.add(Map<String, dynamic>.from(block));
      continue;
    }
    final isText = (block['type'] ?? block['kind']) == 'text';
    if (isText && nextSentenceIdx < sentences.length) {
      newBlocks.add({
        ...Map<String, dynamic>.from(block),
        'text': sentences[nextSentenceIdx++],
      });
    } else {
      newBlocks.add(Map<String, dynamic>.from(block));
    }
  }
  while (nextSentenceIdx < sentences.length) {
    newBlocks.add({'type': 'text', 'text': sentences[nextSentenceIdx++]});
  }
  return {...existing, 'blocks': newBlocks};
}

/// Split a paragraph into sentences by major punctuation. Conservative — keeps
/// short sentences together to avoid breaking text that uses commas lightly.
List<String> _splitIntoSentences(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  final regex = RegExp(r'[^。！？!?\.]+[。！？!?\.]|[^。！？!?\.]+$');
  final matches = regex
      .allMatches(trimmed)
      .map((m) => m.group(0)!.trim())
      .where((s) => s.isNotEmpty);
  final list = matches.toList();
  if (list.isEmpty) return [trimmed];
  return list;
}

/// Best-effort JSON parse that returns null instead of throwing.
Object? _safeParseJson(String raw) {
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}

/// Extract just the text content of text blocks for audit logging.
List<String> _extractTextBlocks(String presentationJson) {
  final parsed = _safeParseJson(presentationJson);
  if (parsed is! Map) return const [];
  final rawBlocks = parsed['blocks'];
  if (rawBlocks is! List) return const [];
  return rawBlocks
      .where((b) => b is Map && (b['type'] ?? b['kind']) == 'text')
      .map((b) => (b as Map)['text']?.toString() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Result of a Record Organizer write.
class RecordPersistResult {
  RecordPersistResult({
    required this.cardIds,
    required this.entityIds,
    required this.assetIds,
    required this.isEmpty,
  });

  final List<String> cardIds;
  final List<String> entityIds;
  final List<String> assetIds;
  final bool isEmpty;
}

/// Source descriptor for a write.
class RecordSource {
  RecordSource({
    required this.sourceKind,
    required this.rawInput,
    this.sourceRef,
    this.recordedPlace,
    DateTime? recordedAt,
  }) : recordedAt = recordedAt ?? DateTime.now();

  /// `record_button` / `fab` / `natural_command` / `import` / `system` / `tool_call`
  final String sourceKind;
  final String rawInput;

  /// Soft reference to upstream object: chat message id / asset id / batch id.
  final String? sourceRef;
  final String? recordedPlace;
  final DateTime recordedAt;
}

class RecordOrganizerServiceV3 {
  RecordOrganizerServiceV3(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();
  static const _organizerVersion = 'record_organizer.v3.0';

  static RecordOrganizerServiceV3? _instance;

  static RecordOrganizerServiceV3 get instance {
    final inst = _instance;
    if (inst == null) {
      throw StateError(
          'RecordOrganizerServiceV3 has not been initialized. Call init() first.');
    }
    return inst;
  }

  static bool get isInitialized => _instance != null;

  static void init(AppDatabase db) {
    _instance = RecordOrganizerServiceV3(db);
    // Schedule a one-time FTS backfill if needed. Non-blocking; runs in the
    // next microtask so it does not delay app startup.
    Future.microtask(() async {
      try {
        // Ensure FTS tables exist before backfilling — this is a no-op if
        // they were already created by migration, but catches cases where
        // the migration ran before createFtsTables was added to the step.
        await _instance!._db.searchDao.createFtsTables();
        // Always backfill on init — upsertMemoryV3Fts is idempotent and
        // cheap for typical card counts.
        final count = await _instance!.reindexAllCards();
        getLogger('RecordOrganizerServiceV3')
            .info('FTS backfill: $count card(s) indexed');
        // One-time cleanup of duplicate active schedule/task/plan cards
        // created before persist-level dedupe existed (2026-08-02).
        final removed = await _instance!.dedupeExistingScheduleCards();
        if (removed > 0) {
          getLogger('RecordOrganizerServiceV3')
              .info('Legacy dedupe: removed $removed duplicate card(s)');
        }
      } catch (_) {
        // Backfill is best-effort; never fail init for it.
      }
    });
  }

  static void reset() => _instance = null;

  /// One-time cleanup of duplicate ACTIVE task/schedule/plan cards that were
  /// created before persist-level dedupe existed (2026-08-02 spider-man
  /// ticket case: the same fact recorded twice produced two cards).
  ///
  /// Also cleans duplicate MONEY cards (expense_entry / income_entry /
  /// shopping_order) since 2026-08-02 — the same dinner recorded twice
  /// (same merchant, same paidAt, same amount) produced duplicate ledger
  /// cards because dedupe only covered to-dos. Money cards additionally
  /// require the SAME amount; two real orders at nearly the same time with
  /// different prices are different orders.
  ///
  /// Groups active cards by (type, normalized title) and, when two cards
  /// share the same time anchor (within 15 min), keeps the OLDEST card and
  /// deletes the rest via [deleteCard] (preserving audit trail). Safe to
  /// call repeatedly — already-merged cards are gone, remaining cards are
  /// never identical.
  ///
  /// Money cards are `event` cards whose structuredFieldsType is a money
  /// domain (expense_entry / income_entry / shopping_order) — the ledger's
  /// card.type is 'event'. Plain life events never participate.
  static const _moneyTypes = {
    'expense_entry',
    'income_entry',
    'shopping_order'
  };

  static bool _isMoneyCard(String fieldsType) =>
      _moneyTypes.contains(fieldsType);

  static bool _isDedupeCard(OrganizedCard card) =>
      card.type == 'task' ||
      card.type == 'schedule' ||
      card.type == 'plan' ||
      (card.type == 'event' && _isMoneyCard(card.structuredFieldsType ?? ''));

  Future<int> dedupeExistingScheduleCards() async {
    var removed = 0;
    try {
      final activeRows = await (_db.select(_db.memoryCards)
            ..where((t) =>
                t.type.isIn(const ['task', 'schedule', 'plan', 'event']) &
                (t.status.equals('active') | t.status.isNull())))
          .get();
      if (activeRows.length < 2) return 0;

      // Load structured fields for all candidates in one pass.
      final sfRows = await (_db.select(_db.memoryCardStructuredFields)
            ..where((t) => t.cardId.isIn(activeRows.map((r) => r.id).toList())))
          .get();
      final sfByCard = <String,
          ({DateTime? anchor, double? amountCny, String? fieldsType})>{};
      for (final sf in sfRows) {
        final parsed = _safeParseJson(sf.fieldsJson);
        if (parsed is! Map<String, dynamic>) {
          sfByCard[sf.cardId] = (
            anchor: null,
            amountCny: null,
            fieldsType: sf.structuredFieldsType
          );
          continue;
        }
        final amountRaw = parsed['amount_cny'];
        sfByCard[sf.cardId] = (
          anchor: _firstTimeAnchor(parsed),
          amountCny: amountRaw is num ? amountRaw.toDouble() : null,
          fieldsType: sf.structuredFieldsType,
        );
      }

      // Group by TYPE first; within each type, use normalized-title
      // CONTAINMENT (not equality) so "看蜘蛛侠电影" and "看蜘蛛侠电影 8月1日
      // 早上" are recognized as the same item. Plain life `event` cards
      // (no money fields) never participate — only event cards carrying a
      // money domain participate, otherwise the group's oldest card is
      // usually a non-money event and the whole group is skipped
      // (2026-08-02 real-device: the oldest event was "排查杯子归属问题bug"
      // with no fields, so all money duplicates survived).
      final byType =
          <String, List<({int createdAt, String id, String title})>>{};
      for (final row in activeRows) {
        final meta = sfByCard[row.id];
        final isMoneyEvent = row.type == 'event' &&
            meta != null &&
            _isMoneyCard(meta.fieldsType ?? '');
        if (row.type == 'event' && !isMoneyEvent) {
          continue;
        }
        byType.putIfAbsent(row.type, () => []).add((
          createdAt: row.createdAt,
          id: row.id,
          title: _normalizeTitle(row.title),
        ));
      }

      for (final entry in byType.entries) {
        final type = entry.key;
        final members = entry.value;
        if (members.length < 2) continue;

        // Cluster members by normalized-title CONTAINMENT before dedupe.
        // Real-device lesson (2026-08-02): grouping by TYPE alone puts every
        // historical money card into one group, so the keeper is always the
        // oldest card ever recorded (e.g. a 07-14 bike ride) and no later
        // duplicate ever falls inside its ±2h window — removed stays 0
        // forever while duplicates pile up. Title clusters ("猪杂粉外卖" vs
        // "猪杂粉外卖 27 元") are the actual comparison unit.
        final clusters = <List<({int createdAt, String id, String title})>>[];
        for (final member in members) {
          var placed = false;
          for (final cluster in clusters) {
            final clusterTitle = cluster.first.title;
            if (clusterTitle.isNotEmpty &&
                member.title.isNotEmpty &&
                (clusterTitle.contains(member.title) ||
                    member.title.contains(clusterTitle))) {
              cluster.add(member);
              placed = true;
              break;
            }
          }
          if (!placed) clusters.add([member]);
        }

        for (final group in clusters) {
          if (group.length < 2) continue;
          group.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          final keeper = group.first;
          final keeperMeta = sfByCard[keeper.id];
          final keeperTitle = keeper.title;
          for (final candidate in group.skip(1)) {
            final candidateMeta = sfByCard[candidate.id];
            if (keeperMeta == null || candidateMeta == null) continue;
            // Event cards participate ONLY when both carry money fields;
            // plain life events must never be merged by title overlap
            // ("早上吃了一个偏硬的桃子" must not die next to a similar title).
            final keeperIsMoney = _isMoneyCard(keeperMeta.fieldsType ?? '');
            final candidateIsMoney =
                _isMoneyCard(candidateMeta.fieldsType ?? '');
            if (type == 'event' && (!keeperIsMoney || !candidateIsMoney)) {
              continue;
            }
            final keeperAnchor = keeperMeta.anchor;
            final candidateAnchor = candidateMeta.anchor;
            if (keeperAnchor == null || candidateAnchor == null) continue;
            if ((candidateAnchor.difference(keeperAnchor).inMinutes).abs() >
                120) {
              continue;
            }
            // Money cards: also require the same amount. Two REAL orders of
            // the same dish at nearly the same time with different prices
            // are different orders — never merge those silently.
            final keeperAmount = keeperMeta.amountCny;
            if (keeperIsMoney &&
                keeperAmount != null &&
                candidateMeta.amountCny != null &&
                (keeperAmount - candidateMeta.amountCny!).abs() > 0.001) {
              continue;
            }
            // Title containment: either direction counts (the keeper may be
            // the shorter or the longer title). expense_entry / shopping_order
            // skip this gate - the LLM rephrases the same expense on every pass
            // so titles diverge ("西塔老太太式样烤肉 335元AA" vs "西塔老太太烤肉
            // 335元AA顺便更新记录了"), and amount+time already uniquely identify
            // the order (2026-08-04 real-device duplicate case). income_entry
            // keeps the title gate: same-amount income from different sources
            // must not merge.
            final keeperAmountKeyed = keeperIsMoney &&
                (keeperMeta.fieldsType == 'expense_entry' ||
                    keeperMeta.fieldsType == 'shopping_order');
            if (!keeperAmountKeyed) {
              final candidateTitle = candidate.title;
              final titlesOverlap = keeperTitle.isNotEmpty &&
                  candidateTitle.isNotEmpty &&
                  (keeperTitle.contains(candidateTitle) ||
                      candidateTitle.contains(keeperTitle));
              if (!titlesOverlap) continue;
            }
            await deleteCard(candidate.id, sourceKind: 'auto_dedupe');
            removed++;
            _logger.info('dedupeExistingScheduleCards: removed ${candidate.id} '
                '(duplicate of ${keeper.id})');
          }
        }
      }
    } catch (e, s) {
      _logger.warning('dedupeExistingScheduleCards failed: $e', e, s);
    }
    return removed;
  }

  /// Trigger a debounced LifeInsight analysis after new data is recorded.
  LifeInsightScheduler? _lifeInsightScheduler;
  Future<void> _triggerLifeInsightAnalysis() async {
    if (!AppDatabase.isInitialized) return;
    _lifeInsightScheduler ??= LifeInsightScheduler(db: AppDatabase.instance);
    _lifeInsightScheduler!.scheduleEventDriven();
  }

  /// Persist an [OrganizedRecord] into the V3 table family.
  ///
  /// Writes within a single transaction. On any failure, nothing is committed.
  /// Caller should have already produced the [organized] payload via the
  /// agent layer; this service only handles persistence.
  Future<RecordPersistResult> persist({
    required OrganizedRecord organized,
    required RecordSource source,
    List<Map<String, String>>? inputMedia,
  }) async {
    if (organized.isEmpty) {
      _logger.info('persist called with empty record; skipping');
      return RecordPersistResult(
        cardIds: const [],
        entityIds: const [],
        assetIds: const [],
        isEmpty: true,
      );
    }

    return _db.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // ── Pre-pass: normalize media assetPaths BEFORE persisting cards ──
      // The LLM may omit media blocks, output UUIDs, or invent paths. The
      // app already knows the ground-truth saved media from inputMedia, so
      // rebuild all media blocks from that source before the card is stored.
      if (inputMedia != null && inputMedia.isNotEmpty) {
        for (var i = 0; i < organized.cards.length; i++) {
          final card = organized.cards[i];
          card.presentationModule['blocks'] = _normalizePresentationMediaBlocks(
            card.presentationModule['blocks'],
            inputMedia,
          );

          // Inject image analysis text into retrievalText so FTS can match
          // against what the image contains, not just the user's raw text.
          final analyses = <String>[];
          for (final m in inputMedia) {
            final analysis = m['analysis'];
            if (analysis != null && analysis.isNotEmpty) {
              analyses.add(analysis);
            }
          }
          if (analyses.isNotEmpty) {
            final existing = card.retrievalText.trim();
            card.retrievalText = '$existing\n[图片内容：${analyses.join("；")}]';
          }
        }
      }

      final cardIds = <String>[];
      final entityIds = <String>[];

      // ── Dedupe pass: reuse an existing active card that describes the
      // same anchored event, instead of creating a duplicate. Covers
      // task/schedule/plan AND money cards (expense_entry / income_entry /
      // shopping_order — a re-stated expense is the most common duplicate;
      // 2026-08-02: "冒菜西施麻辣烫 40.3 元" recorded at 19:56 and again at
      // 20:33 with the same paidAt and amount produced two ledger cards).
      // Money cards additionally require the SAME amount (two real orders at
      // the same time with different prices are different orders).
      final dupLookup = <int, String>{}; // new card index -> existing card id
      for (var i = 0; i < organized.cards.length; i++) {
        final card = organized.cards[i];
        if (!_isDedupeCard(card)) {
          continue;
        }
        final anchor = _firstTimeAnchor(card.structuredFields);
        if (anchor == null) continue;
        final amountRaw = card.structuredFields?['amount_cny'];
        final existingId = await _findDuplicateActiveCard(
          type: card.type,
          anchorMs: anchor.millisecondsSinceEpoch,
          title: card.title,
          structuredFieldsType: card.structuredFieldsType,
          amountCny:
              _isMoneyCard(card.structuredFieldsType ?? '') && amountRaw is num
                  ? amountRaw.toDouble()
                  : null,
        );
        if (existingId != null) {
          dupLookup[i] = existingId;
          _logger.info(
            'persist: card "${card.title}" (${card.type}, $anchor) duplicates '
            'existing active card $existingId — reusing instead of creating.',
          );
        }
      }

      for (var i = 0; i < organized.cards.length; i++) {
        final card = organized.cards[i];
        final reusedId = dupLookup[i];
        if (reusedId != null) {
          cardIds.add(reusedId);
          continue;
        }
        final cardId = _uuid.v4();
        cardIds.add(cardId);

        await _db.into(_db.memoryCards).insert(
              MemoryCardsCompanion.insert(
                id: cardId,
                memoryScope: const Value('user_truth'),
                type: card.type,
                title: card.title,
                dropletLabel: card.dropletLabel,
                presentationModule: jsonEncode(card.presentationModule),
                retrievalText: card.retrievalText,
                valence: card.valence,
                arousal: card.arousal,
                status: Value(card.status),
                needsFollowUp: Value(card.needsFollowUp != null
                    ? jsonEncode(card.needsFollowUp)
                    : null),
                createdAt: now,
                updatedAt: now,
              ),
            );

        await _db.into(_db.memoryCardSources).insert(
              MemoryCardSourcesCompanion.insert(
                cardId: cardId,
                rawInput: source.rawInput,
                recordedAt: source.recordedAt.millisecondsSinceEpoch,
                recordedPlace: Value(source.recordedPlace),
                sourceRef: Value(source.sourceRef),
                sourceKind: source.sourceKind,
              ),
            );

        if (card.structuredFieldsType != null &&
            card.structuredFields != null &&
            card.structuredFields!.isNotEmpty) {
          await _db.into(_db.memoryCardStructuredFields).insert(
                MemoryCardStructuredFieldsCompanion.insert(
                  cardId: cardId,
                  structuredFieldsType: card.structuredFieldsType!,
                  fieldsJson: jsonEncode(card.structuredFields),
                  generatedByVersion: const Value(_organizerVersion),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        }

        for (final link in card.entityLinks) {
          final entityId = await _resolveEntity(link, now: now);
          entityIds.add(entityId);
          await _db.into(_db.memoryEntityLinks).insert(
                MemoryEntityLinksCompanion.insert(
                  id: _uuid.v4(),
                  sourceTable: 'memory_cards',
                  sourceId: cardId,
                  entityId: entityId,
                  relation: link.relation,
                  confidence: Value(link.confidence),
                  createdAt: now,
                ),
              );
        }

        // Audit log entry
        await _db.into(_db.memoryCardOperations).insert(
              MemoryCardOperationsCompanion.insert(
                id: _uuid.v4(),
                cardId: cardId,
                operationType: 'create',
                payload: jsonEncode({
                  'card': card.toJson(),
                  'source': {
                    'sourceKind': source.sourceKind,
                    'sourceRef': source.sourceRef,
                    'recordedAt': source.recordedAt.millisecondsSinceEpoch,
                    'recordedPlace': source.recordedPlace,
                  },
                }),
                sourceKind: source.sourceKind,
                createdAt: now,
              ),
            );

        // FTS index for retrieval
        try {
          await _db.searchDao.upsertMemoryV3Fts(
            cardId: cardId,
            dropletLabel: card.dropletLabel,
            title: card.title,
            retrievalText: card.retrievalText,
          );
        } catch (e, s) {
          _logger.warning('Failed to index card $cardId in FTS', e, s);
        }
      }

      // Create memoryCardAssets links for all input media (the pre-pass
      // already rebuilt display blocks from saved media).
      final assetIds = <String>[];
      if (inputMedia != null) {
        for (var i = 0; i < organized.cards.length; i++) {
          for (final m in inputMedia) {
            final assetId = m['assetId'];
            if (assetId != null) {
              await _ensureAssetLink(
                  cardId: cardIds[i], assetId: assetId, now: now);
              assetIds.add(assetId);
            }
          }
        }
      }

      _logger.info(
          'Persisted ${cardIds.length} memory card(s); ${entityIds.length} entity link(s); ${assetIds.length} asset(s)');

      return RecordPersistResult(
        cardIds: cardIds,
        entityIds: entityIds.toSet().toList(),
        assetIds: assetIds,
        isEmpty: false,
      );
    });
  }

  /// Extract the earliest time anchor from structured fields.
  ///
  /// Mirrors the event-time resolution used by the Schedule panel: only
  /// future-looking / event anchors count for dedupe. Returns null when the
  /// card has no usable time anchor (pure fact-style fields).
  static DateTime? _firstTimeAnchor(Map<String, dynamic>? fields) {
    if (fields == null) return null;
    for (final name in const [
      'startAt',
      'dueAt',
      'remindAt',
      'nextActionAt',
      'occurredAt',
      'endAt',
      'paidAt', // money cards: expense_entry / shopping_order
      'receivedAt', // income_entry
    ]) {
      final raw = fields[name];
      if (raw == null) continue;
      final parsed = DateTime.tryParse(raw.toString());
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// Find an existing ACTIVE (or status-NULL — money cards have no status)
  /// card of the same type whose time anchor is within ±2h. For
  /// expense_entry / shopping_order the key is `type` + `amount_cny` + time
  /// (title ignored - LLM rephrasing breaks title containment, 2026-08-04
  /// 西塔老太太 case). For income_entry and non-money cards the key is
  /// `type` + normalized-title containment + time (same-amount income from
  /// different sources must not merge).
  ///
  /// Returns the existing card id, or null when no match.
  Future<String?> _findDuplicateActiveCard({
    required String type,
    required int anchorMs,
    required String title,
    double? amountCny,
    String? structuredFieldsType,
  }) async {
    const windowMs = 2 * 60 * 60 * 1000; // ±2h
    // Real-device lesson (2026-08-02): an agent FALSELY re-recorded the same
    // three dinners 50 min after the legit records (user message "去晒衣服啦"
    // contained no record request). The LLM's time inference drifted between
    // passes: the same 湖南米粉 bowl got paidAt 19:00 in one pass and 20:00 in
    // the other, so a ±15 min window let the duplicate through. ±2h covers
    // this LLM time-drift while keeping title+amount overlap as the real
    // similarity gate (two true orders of the same dish at the same price
    // within 2h are far rarer than a re-record).
    // No SQL-level title LIKE here: a one-way LIKE('%new%') misses the
    // common case where the EXISTING card has the SHORTER title
    // ("猪杂粉外卖" vs a re-stated "猪杂粉外卖 27 元"), so dedupe silently
    // fails. Load same-type cards and do bidirectional containment in
    // memory (2026-08-02 real-device: the duplicate "猪杂粉外卖 27 元"
    // card was created exactly because the LIKE filter never matched).
    // Amount-keyed dedupe (title skipped) applies only to expense_entry and
    // shopping_order - these describe a single spending event whose title the
    // LLM rephrases on every pass. income_entry keeps the title gate: two
    // same-amount income events from different sources are common and must
    // not merge (2026-08-04: article 1000 + video 1000 within 36h).
    final amountKeyedDedupe = amountCny != null &&
        (structuredFieldsType == 'expense_entry' ||
            structuredFieldsType == 'shopping_order');
    final existingRows = await (_db.select(_db.memoryCards)
          ..where((t) =>
              t.type.equals(type) &
              (t.status.equals('active') | t.status.isNull())))
        .get();
    if (existingRows.isEmpty) return null;

    final normalized = _normalizeTitle(title);
    for (final row in existingRows) {
      // Money cards skip the title gate entirely; non-money cards require
      // bidirectional title containment (real-device 2026-08-02: a one-way
      // SQL LIKE('%new%') missed the case where the EXISTING card had the
      // SHORTER title "猪杂粉外卖" vs a re-stated "猪杂粉外卖 27 元").
      if (!amountKeyedDedupe) {
        final existingNormalized = _normalizeTitle(row.title);
        final titleOverlaps = normalized.isNotEmpty &&
            existingNormalized.isNotEmpty &&
            (normalized.contains(existingNormalized) ||
                existingNormalized.contains(normalized));
        if (!titleOverlaps) continue;
      }

      // Compare time anchors from structured fields.
      final sf = await (_db.select(_db.memoryCardStructuredFields)
            ..where((t) => t.cardId.equals(row.id)))
          .getSingleOrNull();
      if (sf == null) continue;
      final fields = _safeParseJson(sf.fieldsJson);
      final existingAnchor =
          fields is Map<String, dynamic> ? _firstTimeAnchor(fields) : null;
      if (existingAnchor == null) continue;
      if ((existingAnchor.millisecondsSinceEpoch - anchorMs).abs() > windowMs) {
        continue;
      }
      // Money cards: same amount required — two real orders at the same
      // time with different prices are different orders.
      if (amountKeyedDedupe) {
        final targetAmount = amountCny;
        final raw =
            fields is Map<String, dynamic> ? fields['amount_cny'] : null;
        final existingAmount = raw is num ? raw.toDouble() : null;
        if (existingAmount == null ||
            (existingAmount - targetAmount).abs() > 0.001) {
          continue;
        }
      }
      return row.id;
    }
    return null;
  }

  /// Strip whitespace / punctuation / digits for fuzzy title comparison.
  static String _normalizeTitle(String s) {
    var out = s.replaceAll(RegExp(r'[\s\u3000]+'), '');
    out = out.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    return out.replaceAll(RegExp(r'\d+'), '').toLowerCase();
  }

  /// Auto-build `relevantExistingCardSummaries` for the organizer when the
  /// caller did not pass any.
  ///
  /// Root cause (2026-08-02): none of the explicit write paths
  /// (floating ball / record button / LifeMemoryCapture) passed
  /// `relevantExistingCardSummaries`, so the LLM never saw existing cards
  /// before creating new ones — the same fact recorded twice produced two
  /// independent cards. This method closes that gap at the service level so
  /// every caller gets dedupe context for free.
  ///
  /// Uses FTS5 on the raw input; returns up to 5 summaries of EXISTING
  /// active task / schedule / plan / event cards (the types most likely to
  /// collide), formatted compactly for the prompt.
  Future<List<String>> _buildExistingCardSummaries(String rawInput) async {
    if (rawInput.trim().isEmpty) return const [];
    try {
      final hits = await _db.searchDao.searchMemoryV3Cards(
        rawInput,
        limit: 8,
      );
      if (hits.isEmpty) return const [];
      final summaries = <String>[];
      for (final hit in hits) {
        if (summaries.length >= 5) break;
        final cardId = hit['card_id'] as String;
        final row = await (_db.select(_db.memoryCards)
              ..where((t) => t.id.equals(cardId)))
            .getSingleOrNull();
        if (row == null) continue;
        final sf = await (_db.select(_db.memoryCardStructuredFields)
              ..where((t) => t.cardId.equals(cardId)))
            .getSingleOrNull();
        // Only surface cards that could plausibly collide with a new one:
        // schedule-visible to-dos, events, and money cards (a re-stated
        // expense with the same merchant + time is the most common duplicate
        // — 2026-08-02: three dinners recorded twice, money cards were
        // missing here so the LLM never saw the existing cards).
        final isToDo =
            row.type == 'task' || row.type == 'schedule' || row.type == 'plan';
        if (!isToDo && row.type != 'event') {
          continue;
        }
        var extra = '';
        if (sf != null) {
          final fields = _safeParseJson(sf.fieldsJson);
          if (fields is Map<String, dynamic>) {
            final anchor = _firstTimeAnchor(fields);
            if (anchor != null) {
              extra =
                  ' @ ${anchor.toIso8601String()} (status: ${row.status ?? 'active'})';
            }
          }
        }
        summaries.add(
          '「${row.title}」[${row.type}]$extra — ${_extractTextBlocks(row.presentationModule).join(' / ')}',
        );
      }
      return summaries;
    } catch (e) {
      _logger.warning(
          '_buildExistingCardSummaries failed: $e (continuing without dedupe context)');
      return const [];
    }
  }

  /// Idempotent insert into [memoryCardAssets]. No-op if link already exists.
  Future<void> _ensureAssetLink({
    required String cardId,
    required String assetId,
    required int now,
  }) async {
    final existing = await (_db.select(_db.memoryCardAssets)
          ..where((t) => t.cardId.equals(cardId) & t.assetId.equals(assetId)))
        .getSingleOrNull();
    if (existing != null) return;
    await _db.into(_db.memoryCardAssets).insert(
          MemoryCardAssetsCompanion.insert(
            id: _uuid.v4(),
            cardId: cardId,
            assetId: assetId,
            role: 'display',
            createdAt: now,
          ),
        );
  }

  /// Resolve an entity by name (case-insensitive). Creates a new entity in
  /// `status=active` (per V3 § 9.5: user-explicit links skip seed) if no
  /// match found.
  Future<String> _resolveEntity(OrganizedEntityLink link,
      {required int now}) async {
    final existing = await (_db.select(_db.memoryEntities)
          ..where((t) =>
              t.name.lower().equals(link.name.toLowerCase()) &
              t.status.isNotIn(const ['deleted', 'merged'])))
        .getSingleOrNull();

    if (existing != null) {
      // Bump lastMentionedAt + fragmentCount
      await (_db.update(_db.memoryEntities)
            ..where((t) => t.id.equals(existing.id)))
          .write(
        MemoryEntitiesCompanion(
          lastMentionedAt: Value(now),
          fragmentCount: Value(existing.fragmentCount + 1),
        ),
      );
      return existing.id;
    }

    final id = _uuid.v4();
    await _db.into(_db.memoryEntities).insert(
          MemoryEntitiesCompanion.insert(
            id: id,
            name: link.name,
            category: link.category,
            status: const Value('active'),
            relationshipToUser: Value(link.relationshipToUser),
            firstMentionedAt: Value(now),
            lastMentionedAt: Value(now),
            fragmentCount: const Value(1),
            generatedByVersion: const Value(_organizerVersion),
          ),
        );
    return id;
  }

  /// Record a user-edited field as a [UserCorrections] row.
  ///
  /// Per V3 § 11.3, this is the contract that lets us re-generate derivatives
  /// later without losing user judgment.
  Future<void> recordUserCorrection({
    required String targetTable,
    required String targetId,
    required String field,
    Object? oldValue,
    required Object newValue,
    required String correctionType,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.userCorrections).insert(
          UserCorrectionsCompanion.insert(
            id: _uuid.v4(),
            targetTable: targetTable,
            targetId: targetId,
            field: field,
            oldValue: Value(oldValue != null ? jsonEncode(oldValue) : null),
            newValue: jsonEncode(newValue),
            correctionType: correctionType,
            createdAt: now,
          ),
        );
  }

  /// High-level convenience: run the V3 Record Organizer agent on [rawInput]
  /// and persist the resulting [OrganizedRecord].
  ///
  /// This is the single end-to-end entry point that explicit write paths
  /// (record button / floating ball / natural command / external import)
  /// should call. Picks up model config from the caller (per V3 § 10.3
  /// "记忆抽取" function category — caller chooses which user-configured
  /// model to pass in).
  Future<RecordPersistResult> organizeAndPersist({
    required LLMClient client,
    required ModelConfig modelConfig,
    required RecordSource source,
    List<String> relevantExistingCardSummaries = const [],
    List<String> recentEntityNames = const [],
    List<Map<String, String>>? inputMedia,
    RecordOrganizerAgentV3 agent = const RecordOrganizerAgentV3(),
  }) async {
    // Auto-build dedupe context when the caller did not pass any. Without
    // this, the organizer creates a fresh card for every write — recording
    // the same fact twice yields two cards (2026-08-02 spider-man ticket bug).
    if (relevantExistingCardSummaries.isEmpty) {
      relevantExistingCardSummaries =
          await _buildExistingCardSummaries(source.rawInput);
      if (relevantExistingCardSummaries.isNotEmpty) {
        _logger.info(
            'organizeAndPersist: auto-built ${relevantExistingCardSummaries.length} '
            'existing card summary(s) for dedupe context');
      }
    }

    // Register media files as Assets so the LLM can reference them by ID.
    List<Map<String, String>>? enrichedMedia;
    if (inputMedia != null && inputMedia.isNotEmpty) {
      enrichedMedia = [];
      for (final m in inputMedia) {
        _logger.info(
            '_registerMediaAssets: processing ${m['kind']} path=${m['path']}');
        final assetId = _uuid.v4();
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        await _db.into(_db.assets).insert(
              AssetsCompanion.insert(
                id: assetId,
                assetType: m['kind'] ?? 'image',
                storagePath: Value(m['path']),
                originatorRef: Value(source.sourceRef),
                createdAt: nowMs,
              ),
            );
        _logger.info(
            '_registerMediaAssets: inserted asset $assetId storagePath=${m['path']}');
        enrichedMedia.add({
          ...m,
          'assetId': assetId,
        });
      }
    } else {
      _logger.info('_registerMediaAssets: inputMedia is null or empty');
    }

    final organized = await agent.organize(
      client: client,
      modelConfig: modelConfig,
      rawInput: source.rawInput,
      now: source.recordedAt,
      relevantExistingCardSummaries: relevantExistingCardSummaries,
      recentEntityNames: recentEntityNames,
      inputMedia: enrichedMedia,
    );
    _logger.info('organizeAndPersist: ${organized.cards.length} card(s), '
        'inputMedia: ${enrichedMedia != null ? enrichedMedia.map((m) => '${m['kind']}:${m['path']}').join(', ') : 'none'}');
    for (var i = 0; i < organized.cards.length; i++) {
      _logger.info('card[$i] type=${organized.cards[i].type} '
          'blocks=${jsonEncode(organized.cards[i].presentationModule['blocks'])}');
    }
    final result = await persist(
      organized: organized,
      source: source,
      inputMedia: enrichedMedia,
    );
    if (!result.isEmpty) {
      unawaited(
        _bridgeToLedger(
          organized: organized,
          cardIds: result.cardIds,
          source: source,
        ).catchError((error) {
          _logger.warning(
            'organizeAndPersist: ledger bridge failed: $error',
          );
        }),
      );
      unawaited(
        ProactiveOutingService.instance.refreshSchedule().catchError((error) {
          _logger.warning(
            'organizeAndPersist: proactive outing refresh failed: $error',
          );
          return 0;
        }),
      );
      // Trigger LifeInsight event-driven analysis after new data is recorded.
      unawaited(
        _triggerLifeInsightAnalysis().catchError((error) {
          _logger.fine(
            'organizeAndPersist: LifeInsight trigger failed: $error',
          );
        }),
      );
      // Rebuild menstrual cycle rhythm if any card is a menstrual_record.
      if (organized.cards.any((c) =>
          c.structuredFieldsType == 'menstrual_record')) {
        unawaited(
          _rebuildMenstrualRhythm().catchError((error) {
            _logger.warning(
              'organizeAndPersist: menstrual rhythm rebuild failed: $error',
            );
          }),
        );
      }
    }
    return result;
  }

  /// Rebuild the `menstrual_cycle` rhythm from surviving `menstrual_record`
  /// cards. Safe to call repeatedly - idempotent.
  Future<void> _rebuildMenstrualRhythm() async {
    if (!UserRhythmService.isInitialized) return;
    final count =
        await UserRhythmService.instance.rebuildMenstrualRhythmFromCards();
    _logger.info(
        'organizeAndPersist: menstrual rhythm rebuilt ($count cycles)');
  }

  /// Bridge financial memory cards to the shared AI finance ledger.
  ///
  /// When a user records an expense, shopping order or income via any
  /// explicit write path (floating ball, record button, natural command),
  /// this automatically creates a corresponding ledger entry so the finance
  /// panel stays in sync without requiring a separate manual "记一笔" step.
  ///
  /// Only `expense_entry`, `shopping_order` and `income_entry` structured
  /// field types are bridged. Expenses/shopping map to `expense`, income maps
  /// to `income`. The AI share defaults to 0 (pure user money movement).
  /// For income, if the Record Organizer extracted an `ai_share_ratio`
  /// (only present when the user explicitly stated a split), the bridge
  /// computes aiAmount = totalAmount × ratio and stores the contribution
  /// descriptions. The companion can still adjust later via AiFinanceRecord.
  Future<void> _bridgeToLedger({
    required OrganizedRecord organized,
    required List<String> cardIds,
    required RecordSource source,
  }) async {
    final financeService = AiFinanceService(db: _db);
    for (var i = 0; i < organized.cards.length; i++) {
      final card = organized.cards[i];
      final sfType = card.structuredFieldsType;
      final cardId = i < cardIds.length ? cardIds[i] : null;
      if (sfType != 'expense_entry' &&
          sfType != 'shopping_order' &&
          sfType != 'income_entry') {
        continue;
      }

      final fields = card.structuredFields;
      if (fields == null) {
        _logger.warning(
          '_bridgeToLedger: skipped card ${cardId ?? '?'} ($sfType) — '
          'no structuredFields extracted; card was saved to Memory Review '
          'but will NOT appear in the ledger.',
        );
        continue;
      }

      final amountRaw = fields['amount_cny'];
      if (amountRaw == null) {
        _logger.warning(
          '_bridgeToLedger: skipped card ${cardId ?? '?'} ($sfType) — '
          'amount_cny missing from structuredFields; card was saved to '
          'Memory Review but will NOT appear in the ledger.',
        );
        continue;
      }
      final amount = (amountRaw is num)
          ? amountRaw.toDouble()
          : double.tryParse('$amountRaw');
      if (amount == null || amount <= 0) {
        _logger.warning(
          '_bridgeToLedger: skipped card ${cardId ?? '?'} ($sfType) — '
          'amount_cny "$amountRaw" is not a valid positive number; card was '
          'saved to Memory Review but will NOT appear in the ledger.',
        );
        continue;
      }

      final purpose = card.title;

      // Parse occurredAt from structured fields.
      // expense_entry/shopping_order use `paidAt`; income_entry uses `receivedAt`.
      DateTime? occurredAt;
      final timeRaw =
          fields['paidAt'] as String? ?? fields['receivedAt'] as String?;
      if (timeRaw != null) {
        occurredAt = DateTime.tryParse(timeRaw);
      }
      occurredAt ??= source.recordedAt;

      final isIncome = sfType == 'income_entry';

      // For income, check if the user explicitly stated a companion share.
      // The Record Organizer extracts `ai_share_ratio` (0.0–1.0) only when
      // the user mentions a split; absent means pure user income (aiAmount 0).
      double aiAmount = 0;
      double? contributionRatio;
      String? myContributionDesc;
      String? aiContributionDesc;
      if (isIncome) {
        final ratioRaw = fields['ai_share_ratio'];
        if (ratioRaw != null) {
          final ratio = (ratioRaw is num)
              ? ratioRaw.toDouble()
              : double.tryParse('$ratioRaw');
          if (ratio != null && ratio > 0 && ratio <= 1) {
            contributionRatio = ratio;
            aiAmount = (amount * ratio).clamp(0.0, amount).toDouble();
            myContributionDesc = fields['my_contribution'] as String?;
            aiContributionDesc = fields['ai_contribution'] as String?;
          }
        }
      }

      try {
        await financeService.recordEntry(
          characterId: 'system:card_bridge',
          entryType: isIncome ? 'income' : 'expense',
          totalAmount: amount,
          aiAmount: aiAmount,
          contributionRatio: contributionRatio,
          myContributionDesc: myContributionDesc,
          aiContributionDesc: aiContributionDesc,
          purpose: purpose,
          linkedFactId: cardId,
          occurredAt: occurredAt,
        );
        _logger.info(
          '_bridgeToLedger: created ledger entry for card ${cardId ?? '?'} '
          '($sfType, ¥$amount, aiShare ¥$aiAmount, "$purpose")',
        );
      } catch (e) {
        _logger
            .warning('_bridgeToLedger: failed for card ${cardId ?? '?'}: $e');
      }
    }
  }

  /// One-time backfill of ledger entries for finance memory cards that were
  /// recorded while the card→ledger bridge was broken.
  ///
  /// Root cause (2026-07-24): the `transfer_direction` column of
  /// `ai_finance_ledger` was never created on some devices due to a Drift
  /// schema-version reuse bug (see `app_database.dart` v44 migration). While
  /// the column was missing, every `_bridgeToLedger` INSERT threw "no column
  /// named transfer_direction", so `expense_entry` / `shopping_order` /
  /// `income_entry` cards recorded in that window never produced a ledger
  /// row. This method scans the surviving `memory_card_structured_fields`
  /// rows (deleted cards have their structured-fields row removed, so they
  /// are naturally excluded), finds finance cards whose `cardId` is NOT
  /// already referenced by an `ai_finance_ledger.linked_fact_id`, and
  /// re-runs the bridge for each one.
  ///
  /// Idempotency: a `kv_store` marker (`ledger_backfill_v44_done`, bucket
  /// `migration`) is written after a successful run so this never re-runs
  /// on the same database. Safe to call on every startup — the marker check
  /// is the first thing it does.
  Future<int> backfillMissingLedgerEntries() async {
    const markerKey = 'ledger_backfill_v44_done';
    final db = _db;
    final existing = await (db.select(db.kvStore)
          ..where((t) => t.key.equals(markerKey)))
        .getSingleOrNull();
    if (existing != null) {
      _logger.info('backfillMissingLedgerEntries: marker present, skipping');
      return 0;
    }

    const financeTypes = {
      'expense_entry',
      'shopping_order',
      'income_entry',
    };
    final sfRows = await (db.select(db.memoryCardStructuredFields)
          ..where((t) => t.structuredFieldsType.isIn(financeTypes.toList())))
        .get();
    _logger.info(
        'backfillMissingLedgerEntries: ${sfRows.length} finance structured-field row(s) found');

    if (sfRows.isEmpty) {
      await _writeBackfillMarker(db, markerKey);
      return 0;
    }

    // Collect cardIds that already have a ledger row linked to them.
    final ledgerRows = await db.select(db.aiFinanceLedger).get();
    final linkedIds = ledgerRows
        .map((r) => r.linkedFactId)
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toSet();

    var created = 0;
    var skipped = 0;
    for (final sf in sfRows) {
      final cardId = sf.cardId;
      if (linkedIds.contains(cardId)) {
        skipped++;
        continue;
      }
      // Fetch the card row to get the title + scope (skip deleted/missing).
      final card = await (db.select(db.memoryCards)
            ..where((t) => t.id.equals(cardId)))
          .getSingleOrNull();
      if (card == null) {
        // Structured-field row exists but card row is gone (shouldn't happen
        // since deleteCard removes both, but be defensive) — skip.
        skipped++;
        continue;
      }

      final fields = _safeParseJson(sf.fieldsJson);
      if (fields is! Map) {
        skipped++;
        continue;
      }
      final fieldsMap = Map<String, dynamic>.from(fields);

      final sfType = sf.structuredFieldsType;
      final amountRaw = fieldsMap['amount_cny'];
      if (amountRaw == null) {
        skipped++;
        continue;
      }
      final amount = (amountRaw is num)
          ? amountRaw.toDouble()
          : double.tryParse('$amountRaw');
      if (amount == null || amount <= 0) {
        skipped++;
        continue;
      }

      final isIncome = sfType == 'income_entry';
      final purpose = card.title;

      DateTime? occurredAt;
      final timeRaw =
          fieldsMap['paidAt'] as String? ?? fieldsMap['receivedAt'] as String?;
      if (timeRaw != null) {
        occurredAt = DateTime.tryParse(timeRaw);
      }
      occurredAt ??= DateTime.fromMillisecondsSinceEpoch(card.createdAt);

      double aiAmount = 0;
      double? contributionRatio;
      String? myContributionDesc;
      String? aiContributionDesc;
      if (isIncome) {
        final ratioRaw = fieldsMap['ai_share_ratio'];
        if (ratioRaw != null) {
          final ratio = (ratioRaw is num)
              ? ratioRaw.toDouble()
              : double.tryParse('$ratioRaw');
          if (ratio != null && ratio > 0 && ratio <= 1) {
            contributionRatio = ratio;
            aiAmount = (amount * ratio).clamp(0.0, amount).toDouble();
            myContributionDesc = fieldsMap['my_contribution'] as String?;
            aiContributionDesc = fieldsMap['ai_contribution'] as String?;
          }
        }
      }

      final financeService = AiFinanceService(db: db);
      try {
        await financeService.recordEntry(
          characterId: 'system:card_bridge',
          entryType: isIncome ? 'income' : 'expense',
          totalAmount: amount,
          aiAmount: aiAmount,
          contributionRatio: contributionRatio,
          myContributionDesc: myContributionDesc,
          aiContributionDesc: aiContributionDesc,
          purpose: purpose,
          linkedFactId: cardId,
          occurredAt: occurredAt,
        );
        created++;
        _logger.info(
            'backfillMissingLedgerEntries: created ledger entry for card $cardId '
            '($sfType, ¥$amount, aiShare ¥$aiAmount, "$purpose")');
      } catch (e) {
        _logger.warning(
            'backfillMissingLedgerEntries: failed for card $cardId: $e');
      }
    }

    await _writeBackfillMarker(db, markerKey);
    _logger.info(
        'backfillMissingLedgerEntries: done — created $created, skipped $skipped');
    return created;
  }

  Future<void> _writeBackfillMarker(AppDatabase db, String key) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.into(db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: key,
            value: const Value('done'),
            bucket: const Value('migration'),
            updatedAt: Value(now),
          ),
        );
  }

  /// Soft-delete a memory card. Per V3 § 8 contract, this writes a `delete`
  /// audit row and clears the projection. The I-facing query layer must
  /// filter by row existence (no row = deleted = invisible).
  Future<void> deleteCard(String cardId,
      {String sourceKind = 'user_action'}) async {
    // Check card type BEFORE deleting (need to read structured fields).
    bool wasMenstrual = false;
    if (UserRhythmService.isInitialized) {
      final sfRow = await (_db.select(_db.memoryCardStructuredFields)
            ..where((t) => t.cardId.equals(cardId)))
          .getSingleOrNull();
      wasMenstrual = sfRow?.structuredFieldsType == 'menstrual_record';
    }

    await _db.transaction(() async {
      final card = await (_db.select(_db.memoryCards)
            ..where((t) => t.id.equals(cardId)))
          .getSingleOrNull();
      if (card == null) {
        _logger.warning('deleteCard: $cardId not found, no-op');
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.into(_db.memoryCardOperations).insert(
            MemoryCardOperationsCompanion.insert(
              id: _uuid.v4(),
              cardId: cardId,
              operationType: 'delete',
              payload: jsonEncode({'previousScope': card.memoryScope}),
              sourceKind: sourceKind,
              createdAt: now,
            ),
          );
      // Remove projection rows (memory_card_sources, structured_fields,
      // entity_links from this card, relations both directions, card_assets).
      await (_db.delete(_db.memoryCardSources)
            ..where((t) => t.cardId.equals(cardId)))
          .go();
      await (_db.delete(_db.memoryCardStructuredFields)
            ..where((t) => t.cardId.equals(cardId)))
          .go();
      await (_db.delete(_db.memoryEntityLinks)
            ..where((t) =>
                t.sourceTable.equals('memory_cards') &
                t.sourceId.equals(cardId)))
          .go();
      await (_db.delete(_db.memoryCardRelations)
            ..where(
                (t) => t.fromCardId.equals(cardId) | t.toCardId.equals(cardId)))
          .go();
      await (_db.delete(_db.memoryCardAssets)
            ..where((t) => t.cardId.equals(cardId)))
          .go();
      // Card itself
      await (_db.delete(_db.memoryCards)..where((t) => t.id.equals(cardId)))
          .go();
      // FTS index
      try {
        await _db.searchDao.deleteMemoryV3Fts(cardId);
      } catch (e, s) {
        _logger.warning('Failed to remove FTS index for $cardId', e, s);
      }
    });

    if (wasMenstrual) {
      unawaited(_rebuildMenstrualRhythm().catchError((error) {
        _logger.warning('deleteCard: menstrual rhythm rebuild failed: $error');
      }));
    }
  }

  /// Update one or more fields of an existing memory card.
  ///
  /// Writes an `update` operation to the audit log, updates the projection
  /// row(s), and rebuilds the FTS index. Only the fields you pass are changed;
  /// null/absent parameters leave the existing value untouched.
  ///
  /// [structuredFields] and [structuredFieldsType] are updated together: if
  /// you pass one you should pass the other. Passing a non-null [structuredFields]
  /// with null [structuredFieldsType] clears the type.
  ///
  /// Returns the updated card row, or null if [cardId] was not found.
  Future<MemoryCard?> updateCard(
    String cardId, {
    String? title,
    String? retrievalText,
    String? dropletLabel,
    String? type,
    String? status,
    Map<String, dynamic>? structuredFields,
    String? structuredFieldsType,
    Map<String, dynamic>? timeOverrides,
    Map<String, dynamic>? presentationModule,
    String sourceKind = 'companion_edit',
  }) async {
    // Snapshot the card's structured-field type before the update so we can
    // detect a menstrual_record card (whether it's being edited or repurposed).
    String? previousSfType;
    if (UserRhythmService.isInitialized) {
      final sfRow = await (_db.select(_db.memoryCardStructuredFields)
            ..where((t) => t.cardId.equals(cardId)))
          .getSingleOrNull();
      previousSfType = sfRow?.structuredFieldsType;
    }
    final wasPreviouslyMenstrual = previousSfType == 'menstrual_record';
    final touchedFields = structuredFields != null ||
        timeOverrides != null ||
        structuredFieldsType != null;

    final result = await _db.transaction(() async {
      final card = await (_db.select(_db.memoryCards)
            ..where((t) => t.id.equals(cardId)))
          .getSingleOrNull();
      if (card == null) {
        _logger.warning('updateCard: $cardId not found, no-op');
        return null;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final changes = <String, dynamic>{};

      String? newTitle;
      String? newRetrievalText;
      String? newDropletLabel;
      String? newType;
      Value<String?> newStatus = const Value.absent();
      if (title != null && title != card.title) {
        newTitle = title;
        changes['title'] = {'old': card.title, 'new': title};
      }
      if (retrievalText != null && retrievalText != card.retrievalText) {
        newRetrievalText = retrievalText;
        changes['retrievalText'] = {
          'old': card.retrievalText,
          'new': retrievalText
        };
      }
      if (dropletLabel != null && dropletLabel != card.dropletLabel) {
        newDropletLabel = dropletLabel;
        changes['dropletLabel'] = {
          'old': card.dropletLabel,
          'new': dropletLabel
        };
      }
      if (type != null && type != card.type) {
        newType = type;
        changes['type'] = {'old': card.type, 'new': type};
      }
      if (status != null && status != card.status) {
        newStatus = Value(status);
        changes['status'] = {'old': card.status, 'new': status};
      }

      // Update structured fields if requested.
      if (structuredFields != null || timeOverrides != null) {
        final existing = await (_db.select(_db.memoryCardStructuredFields)
              ..where((t) => t.cardId.equals(cardId)))
            .getSingleOrNull();

        // Merge with existing JSON. Time fields in [structuredFields] are
        // stripped — only [timeOverrides] can change them. Unspecified fields
        // are preserved from the original.
        Map<String, dynamic> merged = <String, dynamic>{};
        if (existing != null) {
          final decoded = jsonDecode(existing.fieldsJson);
          if (decoded is Map<String, dynamic>) {
            merged.addAll(decoded);
          }
        }

        if (structuredFields != null) {
          final filtered = Map<String, dynamic>.from(structuredFields);
          for (final key in _timeFieldNames) {
            filtered.remove(key);
          }
          for (final entry in filtered.entries) {
            if (merged[entry.key] != entry.value) {
              changes['structuredFields.${entry.key}'] = {
                'old': merged[entry.key],
                'new': entry.value,
              };
            }
          }
          merged.addAll(filtered);
        }

        if (timeOverrides != null) {
          for (final entry in timeOverrides.entries) {
            if (!_timeFieldNames.contains(entry.key)) {
              _logger.warning(
                'updateCard: timeOverrides ignored non-time field "${entry.key}" on $cardId',
              );
              continue;
            }
            if (merged[entry.key] != entry.value) {
              changes['timeOverrides.${entry.key}'] = {
                'old': merged[entry.key],
                'new': entry.value,
              };
            }
            merged[entry.key] = entry.value;
          }
        }

        final mergedJson = jsonEncode(merged);
        if (existing != null) {
          await (_db.update(_db.memoryCardStructuredFields)
                ..where((t) => t.cardId.equals(cardId)))
              .write(MemoryCardStructuredFieldsCompanion(
            structuredFieldsType: structuredFieldsType != null
                ? Value(structuredFieldsType)
                : const Value.absent(),
            fieldsJson: Value(mergedJson),
            userCorrected: const Value(true),
            updatedAt: Value(now),
          ));
        } else {
          await _db.into(_db.memoryCardStructuredFields).insert(
                MemoryCardStructuredFieldsCompanion.insert(
                  cardId: cardId,
                  structuredFieldsType: structuredFieldsType ?? 'general',
                  fieldsJson: mergedJson,
                  userCorrected: const Value(true),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        }
        if (structuredFieldsType != null) {
          changes['structuredFieldsType'] = structuredFieldsType;
        }
      } else if (structuredFieldsType != null) {
        // Only updating the type without changing fields.
        await (_db.update(_db.memoryCardStructuredFields)
              ..where((t) => t.cardId.equals(cardId)))
            .write(MemoryCardStructuredFieldsCompanion(
          structuredFieldsType: Value(structuredFieldsType),
          userCorrected: const Value(true),
          updatedAt: Value(now),
        ));
        changes['structuredFieldsType'] = structuredFieldsType;
      }

      // Compute presentationModule update.
      //
      // Priority:
      // 1. If caller passed `presentationModule` directly, use it verbatim.
      // 2. Else if `retrievalText` is changing, auto-sync: update text blocks
      //    in the existing presentationModule with the new retrievalText.
      //    Non-text blocks (number/quote/table/media/...) are preserved.
      // 3. Else no presentationModule change.
      String? newPresentationModuleJson;
      if (presentationModule != null) {
        newPresentationModuleJson = jsonEncode(presentationModule);
        if (newPresentationModuleJson != card.presentationModule) {
          changes['presentationModule'] = {
            'old': _safeParseJson(card.presentationModule),
            'new': presentationModule,
          };
        } else {
          newPresentationModuleJson = null;
        }
      } else if (newRetrievalText != null) {
        final newText = newRetrievalText;
        final synced = _syncRetrievalTextIntoBlocks(
          card.presentationModule,
          newText,
        );
        if (synced != null) {
          final json = jsonEncode(synced);
          newPresentationModuleJson = json;
          changes['presentationModule.blocks.text'] = {
            'old': _extractTextBlocks(card.presentationModule),
            'new': _extractTextBlocks(json),
          };
        }
      }

      // Apply card row update if anything changed.
      //
      // NOTE: we deliberately do NOT refresh memory_cards.updatedAt here.
      // That column is the card's "last-modified" time and is used by the
      // Memory Review list as the display+sort key. Refreshing it on every
      // edit would make the card jump to the top of the list and make its
      // list timestamp show the edit time instead of the event time.
      // Modifications are tracked in memory_card_operations (audit log).
      if (changes.isNotEmpty) {
        await (_db.update(_db.memoryCards)..where((t) => t.id.equals(cardId)))
            .write(MemoryCardsCompanion(
          title: newTitle != null ? Value(newTitle) : const Value.absent(),
          retrievalText: newRetrievalText != null
              ? Value(newRetrievalText)
              : const Value.absent(),
          dropletLabel: newDropletLabel != null
              ? Value(newDropletLabel)
              : const Value.absent(),
          type: newType != null ? Value(newType) : const Value.absent(),
          status: newStatus,
          presentationModule: newPresentationModuleJson != null
              ? Value(newPresentationModuleJson)
              : const Value.absent(),
        ));

        // Audit log.
        await _db.into(_db.memoryCardOperations).insert(
              MemoryCardOperationsCompanion.insert(
                id: _uuid.v4(),
                cardId: cardId,
                operationType: 'update',
                payload: jsonEncode(changes),
                sourceKind: sourceKind,
                createdAt: now,
              ),
            );

        // Rebuild FTS with potentially new title/retrievalText/dropletLabel.
        final updatedCard = await (_db.select(_db.memoryCards)
              ..where((t) => t.id.equals(cardId)))
            .getSingle();
        try {
          await _db.searchDao.upsertMemoryV3Fts(
            cardId: cardId,
            dropletLabel: updatedCard.dropletLabel,
            title: updatedCard.title,
            retrievalText: updatedCard.retrievalText,
          );
        } catch (e, s) {
          _logger.warning('updateCard: FTS re-index failed for $cardId', e, s);
        }
        _logger.info(
            'updateCard: updated $cardId, fields: ${changes.keys.join(", ")}');
        return updatedCard;
      }

      _logger.info('updateCard: no changes for $cardId');
      return card;
    });

    // If the card was or is now a menstrual_record and its structured fields
    // or type changed, rebuild the cycle rhythm so the derived projection
    // stays in sync with the (now-corrected) source-of-truth card.
    if (result != null && UserRhythmService.isInitialized) {
      String? currentSfType;
      try {
        final sfRow = await (_db.select(_db.memoryCardStructuredFields)
              ..where((t) => t.cardId.equals(cardId)))
            .getSingleOrNull();
        currentSfType = sfRow?.structuredFieldsType;
      } catch (_) {}
      final isMenstrual = currentSfType == 'menstrual_record';
      if (isMenstrual ||
          (wasPreviouslyMenstrual && touchedFields)) {
        unawaited(_rebuildMenstrualRhythm().catchError((error) {
          _logger.warning('updateCard: menstrual rhythm rebuild failed: $error');
        }));
      }
    }
    return result;
  }

  /// Rebuild FTS indexes for all existing memory cards.
  ///
  /// Call once after the FTS5 virtual table is first created (migration has no
  /// mechanism to backfill virtual tables), or anytime the index is suspected
  /// to be out of sync.
  Future<int> reindexAllCards() async {
    final rows = await _db.select(_db.memoryCards).get();
    var count = 0;
    for (final row in rows) {
      try {
        await _db.searchDao.upsertMemoryV3Fts(
          cardId: row.id,
          dropletLabel: row.dropletLabel,
          title: row.title,
          retrievalText: row.retrievalText,
        );
        count++;
      } catch (e, s) {
        _logger.warning('reindexAllCards: failed for ${row.id}', e, s);
      }
    }
    _logger.info('reindexAllCards: indexed $count/${rows.length} cards');
    return count;
  }
}

List<Map<String, dynamic>> _normalizePresentationMediaBlocks(
  Object? rawBlocks,
  List<Map<String, String>> inputMedia,
) {
  final mediaBlocks = _groundTruthMediaBlocks(inputMedia);
  final contentBlocks = rawBlocks is List
      ? rawBlocks
          .whereType<Object>()
          .map((item) => item is Map
              ? Map<String, dynamic>.from(item)
              : <String, dynamic>{})
          .where((block) => block.isNotEmpty && !_isMediaBlock(block))
          .toList(growable: false)
      : const <Map<String, dynamic>>[];

  if (mediaBlocks.isEmpty) return contentBlocks;
  return [...mediaBlocks, ...contentBlocks];
}

List<Map<String, dynamic>> _groundTruthMediaBlocks(
  List<Map<String, String>> inputMedia,
) {
  final seenPaths = <String>{};
  final blocks = <Map<String, dynamic>>[];
  for (final media in inputMedia) {
    final path = media['path'] ?? media['storagePath'] ?? media['assetPath'];
    if (path == null || path.trim().isEmpty || !seenPaths.add(path)) {
      continue;
    }
    final kind = media['kind'];
    blocks.add({
      'type': 'media',
      'assetPath': path,
      'kind': kind == null || kind == 'media' ? 'image' : kind,
    });
  }
  return blocks;
}

bool _isMediaBlock(Map<String, dynamic> block) {
  final blockType = block['type']?.toString() ?? block['kind']?.toString();
  return blockType == 'media';
}
