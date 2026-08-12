import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'offline_tts_model_installer.dart';

/// A deliberately small, reader-focused lab for comparing local Kokoro voices.
///
/// Model lifecycle and synthesis live here so the eventual reader TTS service
/// can reuse the same verified files without coupling itself to the lab UI.
class BookTtsBakeoffService {
  BookTtsBakeoffService({
    Directory? supportDirectory,
    String? downloadUrl,
    Duration retryDelay = const Duration(seconds: 3),
  }) : _installer = OfflineTtsModelInstaller(
          name: _modelDirectoryName,
          downloadUrl: downloadUrl ?? BookTtsBakeoffService.downloadUrl,
          modelRelativePath: 'model.int8.onnx',
          modelSha256: _modelSha256,
          requiredFiles: const [
            'model.int8.onnx',
            'voices.bin',
            'tokens.txt',
            'lexicon-zh.txt',
            'espeak-ng-data',
          ],
          baseDirectory: supportDirectory,
          retryDelay: retryDelay,
        );

  static const modelName = 'Kokoro v1.1 中文 int8';
  static const installedSizeLabel = '约 215 MB';
  static const downloadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-multi-lang-v1_1.tar.bz2';
  static const _modelDirectoryName = 'kokoro-int8-multi-lang-v1_1';
  static const _modelSha256 =
      'bda15858163726a492d02a9a727bc263551b86ac77f90812c4b30ff41d380e26';

  static const testText = '雨停以后，院子里的石榴树还在滴水。林夏把书翻到折角的那一页，轻声说：“我们从这里继续，好吗？”'
      '钟表刚过七点二十分，远处的列车慢慢驶进站台。她停了一会儿，又念道：'
      '“有些路并不是为了抵达，而是让同行的人，听见彼此的脚步。”';

  static const candidates = <BookTtsCandidate>[
    BookTtsCandidate(label: 'A', speakerId: 3),
    BookTtsCandidate(label: 'B', speakerId: 30),
    BookTtsCandidate(label: 'C', speakerId: 54),
  ];

  final OfflineTtsModelInstaller _installer;

  Future<Directory> get modelDirectory => _installer.modelDirectory;

  Future<bool> isModelReady() => _installer.isReady();

  Future<int> installedBytes() => _installer.installedBytes();

  /// Downloads, stream-extracts, and verifies the model before publishing it.
  Future<void> downloadAndPrepare({
    required ValueChanged<BookTtsInstallProgress> onProgress,
  }) =>
      _installer.downloadAndPrepare(
        onProgress: (progress) =>
            onProgress(BookTtsInstallProgress(progress.value, progress.message)),
      );

  Future<BookTtsSampleResult> generateSample({
    required BookTtsCandidate candidate,
    required double speed,
  }) async {
    if (!await isModelReady()) {
      throw StateError('本地音色模型尚未准备好');
    }
    final root = await modelDirectory;
    final cache = Directory(
        path.join((await _installer.baseDirectory).path, 'samples', 'kokoro'));
    await cache.create(recursive: true);
    final speedKey = speed.toStringAsFixed(2).replaceAll('.', '_');
    final output =
        File(path.join(cache.path, '${candidate.label}_$speedKey.wav'));

    final result = await Isolate.run(() => _generateKokoroSample({
          'root': root.path,
          'output': output.path,
          'text': testText,
          'speakerId': candidate.speakerId,
          'speed': speed,
        }));
    return BookTtsSampleResult.fromJson(result);
  }

  Future<void> deleteModelAndSamples() async {
    await _installer.deleteModel();
    final base = await _installer.baseDirectory;
    final samples = Directory(path.join(base.path, 'samples', 'kokoro'));
    if (await samples.exists()) await samples.delete(recursive: true);
  }

  /// Test seam: downloads [uri] into [target] with the same resume/retry logic
  /// used for the model archive.
  @visibleForTesting
  Future<void> downloadTo(
    Uri uri,
    File target, {
    required ValueChanged<double> onProgress,
  }) =>
      _installer.downloadTo(uri, target, onProgress: onProgress);
}

Map<String, Object> _generateKokoroSample(Map<String, Object> args) {
  final root = args['root']! as String;
  final output = args['output']! as String;
  final text = args['text']! as String;
  final speakerId = args['speakerId']! as int;
  final speed = args['speed']! as double;
  final beforeRss = ProcessInfo.currentRss;
  final initWatch = Stopwatch()..start();

  sherpa.initBindings();
  final model = sherpa.OfflineTtsModelConfig(
    kokoro: sherpa.OfflineTtsKokoroModelConfig(
      model: path.join(root, 'model.int8.onnx'),
      voices: path.join(root, 'voices.bin'),
      tokens: path.join(root, 'tokens.txt'),
      dataDir: path.join(root, 'espeak-ng-data'),
      lexicon: path.join(root, 'lexicon-zh.txt'),
    ),
    numThreads: 2,
    debug: false,
    provider: 'cpu',
  );
  final tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(model: model));
  final initMs = initWatch.elapsedMilliseconds;
  final generationWatch = Stopwatch()..start();
  int? firstChunkMs;
  try {
    final audio = tts.generateWithConfig(
      text: text,
      config: sherpa.OfflineTtsGenerationConfig(
        sid: speakerId,
        speed: speed,
      ),
      onProgress: (samples, progress) {
        firstChunkMs ??= generationWatch.elapsedMilliseconds;
        return 1;
      },
    );
    final generationMs = generationWatch.elapsedMilliseconds;
    if (audio.samples.isEmpty || audio.sampleRate <= 0) {
      throw StateError('音频生成失败');
    }
    final ok = sherpa.writeWave(
      filename: output,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );
    if (!ok) throw FileSystemException('无法保存试听音频', output);
    final audioDurationMs =
        (audio.samples.length * 1000 / audio.sampleRate).round();
    return <String, Object>{
      'audioPath': output,
      'initMs': initMs,
      'firstChunkMs': firstChunkMs ?? generationMs,
      'generationMs': generationMs,
      'audioDurationMs': audioDurationMs,
      'peakRssBytes': ProcessInfo.currentRss > beforeRss
          ? ProcessInfo.currentRss - beforeRss
          : 0,
    };
  } finally {
    tts.free();
  }
}

@immutable
class BookTtsCandidate {
  const BookTtsCandidate({required this.label, required this.speakerId});

  final String label;
  final int speakerId;
}

/// Install progress for a reader TTS model package.
typedef BookTtsInstallProgress = OfflineTtsInstallProgress;

@immutable
class BookTtsSampleResult {
  const BookTtsSampleResult({
    required this.audioPath,
    required this.initMs,
    required this.firstChunkMs,
    required this.generationMs,
    required this.audioDurationMs,
    required this.peakRssBytes,
  });

  factory BookTtsSampleResult.fromJson(Map<String, Object> json) =>
      BookTtsSampleResult(
        audioPath: json['audioPath']! as String,
        initMs: json['initMs']! as int,
        firstChunkMs: json['firstChunkMs']! as int,
        generationMs: json['generationMs']! as int,
        audioDurationMs: json['audioDurationMs']! as int,
        peakRssBytes: json['peakRssBytes']! as int,
      );

  final String audioPath;
  final int initMs;
  final int firstChunkMs;
  final int generationMs;
  final int audioDurationMs;
  final int peakRssBytes;

  double get realTimeFactor =>
      audioDurationMs == 0 ? 0 : generationMs / audioDurationMs;

  Map<String, Object> toJson() => {
        'audioPath': audioPath,
        'initMs': initMs,
        'firstChunkMs': firstChunkMs,
        'generationMs': generationMs,
        'audioDurationMs': audioDurationMs,
        'peakRssBytes': peakRssBytes,
      };
}

@immutable
class BookTtsVoiceRating {
  const BookTtsVoiceRating({
    this.naturalness = 3,
    this.emotion = 3,
    this.pronunciation = 3,
    this.longListening = 3,
    this.dialogue = 3,
  });

  factory BookTtsVoiceRating.fromJson(Map<String, dynamic> json) =>
      BookTtsVoiceRating(
        naturalness: json['naturalness'] as int? ?? 3,
        emotion: json['emotion'] as int? ?? 3,
        pronunciation: json['pronunciation'] as int? ?? 3,
        longListening: json['longListening'] as int? ?? 3,
        dialogue: json['dialogue'] as int? ?? 3,
      );

  final int naturalness;
  final int emotion;
  final int pronunciation;
  final int longListening;
  final int dialogue;

  double get average =>
      (naturalness + emotion + pronunciation + longListening + dialogue) / 5;

  BookTtsVoiceRating copyWith({
    int? naturalness,
    int? emotion,
    int? pronunciation,
    int? longListening,
    int? dialogue,
  }) =>
      BookTtsVoiceRating(
        naturalness: naturalness ?? this.naturalness,
        emotion: emotion ?? this.emotion,
        pronunciation: pronunciation ?? this.pronunciation,
        longListening: longListening ?? this.longListening,
        dialogue: dialogue ?? this.dialogue,
      );

  Map<String, int> toJson() => {
        'naturalness': naturalness,
        'emotion': emotion,
        'pronunciation': pronunciation,
        'longListening': longListening,
        'dialogue': dialogue,
      };
}

String encodeBookTtsBakeoffReport({
  required double speed,
  required Map<String, BookTtsVoiceRating> ratings,
  required Map<String, BookTtsSampleResult> results,
}) {
  final payload = <String, Object>{
    'version': 1,
    'model': BookTtsBakeoffService.modelName,
    'speed': speed,
    'createdAt': DateTime.now().toIso8601String(),
    'voices': {
      for (final candidate in BookTtsBakeoffService.candidates)
        candidate.label: {
          'rating': ratings[candidate.label]?.toJson(),
          'metrics': results[candidate.label]?.toJson(),
        },
    },
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}
