/// Embedding service for semantic memory retrieval.
///
/// Calls the user's configured LLM provider embedding API to generate
/// vectors, stores them in [MemoryEmbeddings], and provides cosine
/// similarity search over stored fragment/episode vectors.
///
/// Gracefully degrades: if the provider doesn't support embeddings or
/// the call fails, returns empty results and the caller falls back to FTS.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/llm_client/codex_responses_client.dart' show configureProxy;
import 'package:memex/utils/user_storage.dart';

class EmbeddingService {
  EmbeddingService._();
  static final EmbeddingService instance = EmbeddingService._();

  final Logger _logger = Logger('memory_v3.EmbeddingService');
  final Dio _dio = Dio();
  bool _initialized = false;
  bool _available = false;
  String _provider = '';
  String _model = '';
  String _baseUrl = '';
  String _apiKey = '';
  String? _proxyUrl;
  int _dimension = 0;

  /// Whether the embedding service is ready and the provider supports it.
  bool get isAvailable => _available;

  /// Initialize from the user's default LLM config.
  /// Safe to call multiple times; only re-reads config if not yet initialized.
  Future<void> init({bool force = false}) async {
    if (_initialized && !force) return;
    _initialized = true;

    try {
      final config = await UserStorage.getAgentLLMConfig(
        'record_organizer',
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      _configureFromLLMConfig(config);
      // Auto-backfill: if embedding is available but no vectors stored yet,
      // kick off background backfill for existing fragments.
      if (_available) {
        _maybeAutoBackfill();
      }
    } catch (e) {
      _logger.warning('EmbeddingService init failed: $e');
      _available = false;
    }
  }

  bool _backfillStarted = false;
  void _maybeAutoBackfill() {
    if (_backfillStarted) return;
    _backfillStarted = true;
    // Fire-and-forget: check if embeddings table is empty, backfill if so.
    Future(() async {
      final db = AppDatabase.instance;
      final count = await (db.select(db.memoryEmbeddings)
            ..where((t) => t.targetTable.equals('memory_fragments')))
          .get()
          .then((rows) => rows.length);
      if (count == 0) {
        _logger.info('No fragment embeddings found — starting auto-backfill');
        final generated = await backfillFragmentEmbeddings();
        _logger.info('Auto-backfill complete: $generated embeddings generated');
      }
    }).catchError((e, s) {
      _logger.warning('Auto-backfill failed', e, s);
    });
  }

  void _configureFromLLMConfig(LLMConfig config) {
    _proxyUrl = config.proxyUrl;
    configureProxy(_dio, _proxyUrl);
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 30);

    final effectiveType = LLMConfig.underlyingClientType(config.type) ?? config.type;

    switch (effectiveType) {
      case LLMConfig.typeGemini:
        _provider = 'gemini';
        _model = 'text-embedding-004';
        _baseUrl = config.baseUrl.isNotEmpty
            ? config.baseUrl
            : 'https://generativelanguage.googleapis.com/v1beta';
        _apiKey = config.getEffectiveApiKey();
        _dimension = 768;
        _available = _apiKey.isNotEmpty;
        break;

      case LLMConfig.typeChatCompletion:
      case LLMConfig.typeResponses:
        // OpenAI-compatible — determine embedding model by provider
        _provider = 'openai_compatible';
        _baseUrl = config.baseUrl;
        _apiKey = config.getEffectiveApiKey();
        _model = _inferEmbeddingModel(config);
        _dimension = _model.contains('3-small') ? 1536 : 1024;
        _available = _apiKey.isNotEmpty && _baseUrl.isNotEmpty;
        break;

      default:
        // Claude, Bedrock, OAuth providers — no standard embedding API
        _logger.info(
          'Embedding not supported for provider type: ${config.type}',
        );
        _available = false;
    }

    if (_available) {
      _logger.info(
        'EmbeddingService ready: provider=$_provider model=$_model dim=$_dimension',
      );
    }
  }

  /// Infer the best embedding model ID from the user's chat config.
  String _inferEmbeddingModel(LLMConfig config) {
    // Allow explicit override via extra params
    final override = config.extra['embeddingModel'] as String?;
    if (override != null && override.isNotEmpty) return override;

    // Infer from provider base URL
    final base = config.baseUrl.toLowerCase();
    if (base.contains('moonshot')) return 'moonshot-v1-embedding';
    if (base.contains('dashscope') || base.contains('aliyun')) {
      return 'text-embedding-v3';
    }
    if (base.contains('deepseek')) return 'text-embedding-v3';
    if (base.contains('openrouter')) return 'openai/text-embedding-3-small';
    if (base.contains('localhost') || base.contains('127.0.0.1')) {
      return 'nomic-embed-text'; // Ollama default
    }
    // Default: OpenAI standard
    return 'text-embedding-3-small';
  }

  // ==========================================================================
  // Public API
  // ==========================================================================

  /// Generate embedding for a single text. Returns null on failure.
  Future<Float32List?> embed(String text) async {
    final results = await embedBatch([text]);
    return results.isNotEmpty ? results.first : null;
  }

  /// Generate embeddings for a batch of texts.
  Future<List<Float32List>> embedBatch(List<String> texts) async {
    if (!_available || texts.isEmpty) return const [];
    await init();
    if (!_available) return const [];

    try {
      if (_provider == 'gemini') {
        return await _embedGemini(texts);
      } else {
        return await _embedOpenAICompatible(texts);
      }
    } catch (e, s) {
      _logger.warning('Embedding API call failed: $e', e, s);
      return const [];
    }
  }

  /// Store embedding vector for a target row.
  Future<void> storeEmbedding({
    required String targetTable,
    required String targetId,
    required Float32List vector,
    required String contentHash,
  }) async {
    final db = AppDatabase.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.memoryEmbeddings).insertOnConflictUpdate(
          MemoryEmbeddingsCompanion.insert(
            targetTable: targetTable,
            targetId: targetId,
            vector: _float32ToBlob(vector),
            provider: _provider,
            model: _model,
            dimension: vector.length,
            contentHash: contentHash,
            updatedAt: now,
          ),
        );
  }

  /// Semantic search: embed [query], then find the most similar stored
  /// vectors for [targetTable] rows. Returns (targetId, score) pairs
  /// sorted by descending cosine similarity.
  ///
  /// Returns empty list if embedding is unavailable or query embedding fails.
  Future<List<({String targetId, double score})>> searchSimilar({
    required String query,
    required String targetTable,
    int limit = 12,
    double minScore = 0.25,
  }) async {
    if (!_available) return const [];
    await init();
    if (!_available) return const [];

    final queryVec = await embed(query);
    if (queryVec == null) return const [];

    final db = AppDatabase.instance;
    final rows = await (db.select(db.memoryEmbeddings)
          ..where((t) => t.targetTable.equals(targetTable)))
        .get();

    if (rows.isEmpty) return const [];

    final scored = <({String targetId, double score})>[];
    for (final row in rows) {
      final vec = _blobToFloat32(row.vector);
      if (vec.length != queryVec.length) continue;
      final sim = _cosineSimilarity(queryVec, vec);
      if (sim >= minScore) {
        scored.add((targetId: row.targetId, score: sim));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).toList();
  }

  /// Backfill embeddings for all fragments that don't have one yet.
  /// Call from Lab screen or migration. Returns count of new embeddings.
  Future<int> backfillFragmentEmbeddings({int batchSize = 20}) async {
    if (!_available) return 0;
    await init();
    if (!_available) return 0;

    final db = AppDatabase.instance;
    var total = 0;

    while (true) {
      // Find fragments without embeddings
      final existingIds = await (db.select(db.memoryEmbeddings)
            ..where((t) => t.targetTable.equals('memory_fragments')))
          .get()
          .then((rows) => rows.map((r) => r.targetId).toSet());

      final fragments = await (db.select(db.memoryFragments)
            ..where((t) => t.status.isIn(const ['active', 'consolidated']))
            ..limit(batchSize))
          .get();

      final pending = fragments
          .where((f) => !existingIds.contains(f.id))
          .toList();
      if (pending.isEmpty) break;

      final texts = pending.map((f) => f.content).toList();
      final vectors = await embedBatch(texts);
      if (vectors.isEmpty) break;

      for (var i = 0; i < vectors.length && i < pending.length; i++) {
        await storeEmbedding(
          targetTable: 'memory_fragments',
          targetId: pending[i].id,
          vector: vectors[i],
          contentHash: _contentHash(pending[i].content),
        );
        total++;
      }

      _logger.info('Backfill progress: $total embeddings generated');
      if (vectors.length < pending.length) break; // API returned partial
    }

    _logger.info('Backfill complete: $total new fragment embeddings');
    return total;
  }

  // ==========================================================================
  // Provider implementations
  // ==========================================================================

  Future<List<Float32List>> _embedOpenAICompatible(List<String> texts) async {
    final url = '$_baseUrl/embeddings';
    final response = await _dio.post(
      url,
      options: Options(headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      }),
      data: jsonEncode({
        'model': _model,
        'input': texts,
      }),
    );

    final data = response.data as Map<String, dynamic>;
    final embeddings = data['data'] as List<dynamic>;
    return embeddings.map((e) {
      final vec = (e['embedding'] as List<dynamic>)
          .map((v) => (v as num).toDouble())
          .toList();
      return Float32List.fromList(vec);
    }).toList();
  }

  Future<List<Float32List>> _embedGemini(List<String> texts) async {
    final results = <Float32List>[];
    // Gemini embedContent is single-text; batch via loop
    for (final text in texts) {
      final url = '$_baseUrl/models/$_model:embedContent';
      final response = await _dio.post(
        url,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': _apiKey,
        }),
        data: jsonEncode({
          'content': {
            'parts': [
              {'text': text}
            ]
          }
        }),
      );
      final data = response.data as Map<String, dynamic>;
      final embedding = data['embedding'] as Map<String, dynamic>;
      final values = (embedding['values'] as List<dynamic>)
          .map((v) => (v as num).toDouble())
          .toList();
      results.add(Float32List.fromList(values));
    }
    return results;
  }

  // ==========================================================================
  // Vector math & serialization
  // ==========================================================================

  static double _cosineSimilarity(Float32List a, Float32List b) {
    var dot = 0.0, normA = 0.0, normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = sqrt(normA) * sqrt(normB);
    if (denom == 0) return 0;
    return dot / denom;
  }

  static Uint8List _float32ToBlob(Float32List vec) {
    final bytes = ByteData(vec.length * 4);
    for (var i = 0; i < vec.length; i++) {
      bytes.setFloat32(i * 4, vec[i], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  static Float32List _blobToFloat32(Uint8List blob) {
    final bytes = ByteData.sublistView(blob);
    final count = blob.length ~/ 4;
    final vec = Float32List(count);
    for (var i = 0; i < count; i++) {
      vec[i] = bytes.getFloat32(i * 4, Endian.little);
    }
    return vec;
  }

  static String _contentHash(String content) {
    // Simple hash for staleness detection
    var hash = 0;
    for (var i = 0; i < content.length; i++) {
      hash = (hash * 31 + content.codeUnitAt(i)) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }
}
