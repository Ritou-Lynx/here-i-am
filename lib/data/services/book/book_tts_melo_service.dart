import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'book_tts_bakeoff_service.dart' show BookTtsBakeoffService, BookTtsSampleResult;
import 'offline_tts_model_installer.dart';

/// Local reader voice backed by MeloTTS (sherpa-onnx vits-melo-tts-zh_en).
///
/// A single Chinese/English voice, positioned as the lightweight / low-storage
/// counterpoint to Kokoro in the reader voice bakeoff.
class BookTtsMeloService {
  BookTtsMeloService({
    Directory? supportDirectory,
    String? downloadUrl,
    Duration retryDelay = const Duration(seconds: 3),
  }) : _installer = OfflineTtsModelInstaller(
          name: _modelDirectoryName,
          downloadUrl: downloadUrl ?? BookTtsMeloService.downloadUrl,
          modelRelativePath: 'model.onnx',
          modelSha256: _modelSha256,
          requiredFiles: const ['model.onnx', 'tokens.txt', 'lexicon.txt'],
          baseDirectory: supportDirectory,
          retryDelay: retryDelay,
        );

  static const modelName = 'MeloTTS zh/en';
  static const installedSizeLabel = '约 170 MB';
  static const downloadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-melo-tts-zh_en.tar.bz2';
  static const _modelDirectoryName = 'vits-melo-tts-zh_en';
  static const _modelSha256 =
      'bf30582eb1b012250a35b1a4a80e7dfbcf8485e7bb9de0d95efbbeef0e4ad86d';

  static const testText = BookTtsBakeoffService.testText;

  final OfflineTtsModelInstaller _installer;

  Future<Directory> get modelDirectory => _installer.modelDirectory;

  Future<bool> isModelReady() => _installer.isReady();

  Future<int> installedBytes() => _installer.installedBytes();

  Future<void> downloadAndPrepare({
    required ValueChanged<OfflineTtsInstallProgress> onProgress,
  }) =>
      _installer.downloadAndPrepare(onProgress: onProgress);

  Future<BookTtsSampleResult> generateSample({required double speed}) async {
    if (!await isModelReady()) {
      throw StateError('本地 MeloTTS 模型尚未准备好');
    }
    final root = await modelDirectory;
    final cache = Directory(
        path.join((await _installer.baseDirectory).path, 'samples', 'melo'));
    await cache.create(recursive: true);
    final speedKey = speed.toStringAsFixed(2).replaceAll('.', '_');
    final output = File(path.join(cache.path, 'melo_$speedKey.wav'));

    final result = await Isolate.run(() => _generateMeloSample({
          'root': root.path,
          'output': output.path,
          'text': testText,
          'speed': speed,
        }));
    return BookTtsSampleResult.fromJson(result);
  }

  Future<void> deleteModelAndSamples() async {
    await _installer.deleteModel();
    final base = await _installer.baseDirectory;
    final samples = Directory(path.join(base.path, 'samples', 'melo'));
    if (await samples.exists()) await samples.delete(recursive: true);
  }
}

Map<String, Object> _generateMeloSample(Map<String, Object> args) {
  final root = args['root']! as String;
  final output = args['output']! as String;
  final text = args['text']! as String;
  final speed = args['speed']! as double;
  final beforeRss = ProcessInfo.currentRss;
  final initWatch = Stopwatch()..start();

  sherpa.initBindings();
  final model = sherpa.OfflineTtsModelConfig(
    vits: sherpa.OfflineTtsVitsModelConfig(
      model: path.join(root, 'model.onnx'),
      lexicon: path.join(root, 'lexicon.txt'),
      tokens: path.join(root, 'tokens.txt'),
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
        sid: 0,
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
