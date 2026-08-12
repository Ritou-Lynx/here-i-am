import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// A deliberately small, reader-focused lab for comparing local Kokoro voices.
///
/// Model lifecycle and synthesis live here so the eventual reader TTS service
/// can reuse the same verified files without coupling itself to the lab UI.
class BookTtsBakeoffService {
  BookTtsBakeoffService({Directory? supportDirectory})
      : _supportDirectoryOverride = supportDirectory;

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

  final Directory? _supportDirectoryOverride;

  Future<Directory> _baseDirectory() async {
    final support =
        _supportDirectoryOverride ?? await getApplicationSupportDirectory();
    return Directory(path.join(support.path, 'book_tts'));
  }

  Future<Directory> get modelDirectory async =>
      Directory(path.join((await _baseDirectory()).path, _modelDirectoryName));

  Future<bool> isModelReady() async {
    final root = await modelDirectory;
    final marker = File(path.join(root.path, '.verified'));
    if (!await marker.exists()) return false;
    return _hasRequiredFiles(root);
  }

  Future<int> installedBytes() async {
    final root = await modelDirectory;
    if (!await root.exists()) return 0;
    var total = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Downloads, stream-extracts, and verifies the model before publishing it.
  Future<void> downloadAndPrepare({
    required ValueChanged<BookTtsInstallProgress> onProgress,
  }) async {
    final base = await _baseDirectory();
    await base.create(recursive: true);
    // Keep the compression suffix last: the streaming extractor selects its
    // decoder from the filename extension.
    final archiveFile =
        File(path.join(base.path, '$_modelDirectoryName.part.tar.bz2'));
    final staging =
        Directory(path.join(base.path, '.extracting-$_modelDirectoryName'));
    final destination = await modelDirectory;

    if (await archiveFile.exists()) await archiveFile.delete();
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);

    try {
      onProgress(const BookTtsInstallProgress(0, '正在下载本地音色模型'));
      await _downloadFile(
        Uri.parse(downloadUrl),
        archiveFile,
        onProgress: (value) => onProgress(
          BookTtsInstallProgress(value * 0.82, '正在下载本地音色模型'),
        ),
      );

      onProgress(const BookTtsInstallProgress(0.84, '正在解压模型'));
      await extractFileToDisk(
        archiveFile.path,
        staging.path,
        bufferSize: 1024 * 1024,
      );

      onProgress(const BookTtsInstallProgress(0.92, '正在校验模型完整性'));
      final extractedRoot = await _findExtractedRoot(staging);
      if (extractedRoot == null || !_hasRequiredFiles(extractedRoot)) {
        throw const FormatException('模型包缺少必要文件');
      }
      final digest = await sha256
          .bind(
              File(path.join(extractedRoot.path, 'model.int8.onnx')).openRead())
          .first;
      if (digest.toString() != _modelSha256) {
        throw const FormatException('模型校验失败，请重新下载');
      }

      if (await destination.exists()) await destination.delete(recursive: true);
      if (path.equals(extractedRoot.path, staging.path)) {
        await staging.rename(destination.path);
      } else {
        await extractedRoot.rename(destination.path);
        if (await staging.exists()) await staging.delete(recursive: true);
      }
      await File(path.join(destination.path, '.verified'))
          .writeAsString(_modelSha256, flush: true);
      onProgress(const BookTtsInstallProgress(1, '模型已就绪'));
    } finally {
      if (await archiveFile.exists()) await archiveFile.delete();
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<BookTtsSampleResult> generateSample({
    required BookTtsCandidate candidate,
    required double speed,
  }) async {
    if (!await isModelReady()) {
      throw StateError('本地音色模型尚未准备好');
    }
    final root = await modelDirectory;
    final cache =
        Directory(path.join((await _baseDirectory()).path, 'samples'));
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
    final base = await _baseDirectory();
    if (await base.exists()) await base.delete(recursive: true);
  }

  Future<void> _downloadFile(
    Uri uri,
    File target, {
    required ValueChanged<double> onProgress,
  }) async {
    final client = http.Client();
    IOSink? sink;
    try {
      final response = await client.send(http.Request('GET', uri));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('下载失败（${response.statusCode}）', uri: uri);
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      sink = target.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } finally {
      await sink?.close();
      client.close();
    }
  }

  Future<Directory?> _findExtractedRoot(Directory staging) async {
    if (_hasRequiredFiles(staging)) return staging;
    await for (final entity
        in staging.list(recursive: true, followLinks: false)) {
      if (entity is File && path.basename(entity.path) == 'model.int8.onnx') {
        final root = entity.parent;
        if (_hasRequiredFiles(root)) return root;
      }
    }
    return null;
  }

  bool _hasRequiredFiles(Directory root) {
    const files = [
      'model.int8.onnx',
      'voices.bin',
      'tokens.txt',
      'lexicon-zh.txt',
    ];
    return files
            .every((name) => File(path.join(root.path, name)).existsSync()) &&
        Directory(path.join(root.path, 'espeak-ng-data')).existsSync();
  }
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

@immutable
class BookTtsInstallProgress {
  const BookTtsInstallProgress(this.value, this.message);

  final double value;
  final String message;
}

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
