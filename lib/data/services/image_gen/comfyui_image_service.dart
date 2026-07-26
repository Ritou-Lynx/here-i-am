import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:memex/data/services/image_gen/image_gen_cache.dart';
import 'package:memex/data/services/image_gen/image_gen_provider.dart';
import 'package:memex/utils/user_storage.dart';

/// Image generation via a local ComfyUI instance.
///
/// ComfyUI runs an HTTP API (default http://127.0.0.1:8188) that accepts
/// workflow JSON, queues it, and saves results to disk.  This service builds
/// a minimal txt2img workflow, polls for completion, and downloads the image.
class ComfyUIImageService {
  ComfyUIImageService._();

  static const _defaultUrl = 'http://192.0.2.1:8188';
  static const _defaultModel = 'juggernautXL_ragnarok.safetensors';
  static const _defaultNegative =
      'lowres, bad anatomy, bad hands, bad feet, text, error, worst quality, '
      'low quality, normal quality, jpeg artifacts, signature, watermark, '
      'username, blurry, deformed, disfigured, ugly, duplicate, mutated, '
      'extra limbs, extra arms, extra legs, fused fingers, too many fingers, '
      'long neck, cross-eyed, poorly drawn face, poorly drawn hands, '
      'poorly drawn feet, mutation, cloned face';
  static const _timeout = Duration(minutes: 5);
  static const _pollInterval = Duration(seconds: 2);

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: _timeout,
  ));

  /// Check whether a ComfyUI instance is reachable.
  static Future<bool> isAvailable() async {
    try {
      final url = await _getBaseUrl();
      final resp = await _dio.get(
        '$url/system_stats',
        options: Options(sendTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5)),
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<ImageGenerationResult> generate(
    ImageGenerationRequest request,
  ) async {
    final baseUrl = await _getBaseUrl();
    final model = await _getOrDefault(
      UserStorage.getComfyuiModel,
      _defaultModel,
    );

    // Parse size "WxH"
    final dims = _parseSize(request.size);
    final width = dims[0];
    final height = dims[1];

    // Cache check
    final key = ImageGenCache.cacheKey(
      prompt: request.prompt,
      provider: 'comfyui',
      model: model,
      size: request.size,
      style: request.style,
    );
    final cached = await ImageGenCache.lookup(key);
    if (cached != null) {
      debugPrint('[ImageGen] ComfyUI cache HIT key=$key');
      final fileBytes = await File(cached).readAsBytes();
      return ImageGenerationResult(
        images: [Uint8List.sublistView(fileBytes)],
        providerModel: model,
      );
    }

    // Build workflow JSON (API format)
    final negative = request.negativePrompt ?? _defaultNegative;
    final seed = Random().nextInt(1 << 30);
    final workflow = _buildWorkflow(
      model: model,
      positive: request.prompt,
      negative: negative,
      width: width,
      height: height,
      seed: seed,
      steps: 35,
      cfg: 6,
    );

    // Submit prompt
    final clientId = 'memex-${DateTime.now().millisecondsSinceEpoch}';
    final submitBody = jsonEncode({
      'prompt': workflow,
      'client_id': clientId,
    });
    debugPrint('[ImageGen] ComfyUI submit: model=$model ${width}x$height seed=$seed');

    final submitResp = await _dio.post(
      '$baseUrl/prompt',
      data: submitBody,
      options: Options(
        headers: {'Content-Type': 'application/json'},
        responseType: ResponseType.bytes,
      ),
    );
    final submitRaw = submitResp.data as List<int>;
    final submitData =
        jsonDecode(String.fromCharCodes(submitRaw)) as Map<String, dynamic>;
    final promptId = submitData['prompt_id'] as String?;
    if (promptId == null) {
      throw Exception('ComfyUI did not return a prompt_id');
    }
    debugPrint('[ImageGen] ComfyUI queued: $promptId');

    // Poll history until the prompt completes
    final images = await _pollForImages(baseUrl, promptId);
    if (images.isEmpty) {
      throw Exception('ComfyUI produced no images');
    }

    // Cache & return
    debugPrint('[ImageGen] ComfyUI success: ${images.length} image(s), ${images.first.length} bytes');
    for (final img in images) {
      try {
        await ImageGenCache.store(key, img);
      } catch (e) {
        debugPrint('[ImageGen] ComfyUI cache store failed (non-fatal): $e');
      }
    }
    return ImageGenerationResult(
      images: images,
      providerModel: model,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Future<String> _getBaseUrl() async {
    return await _getOrDefault(UserStorage.getComfyuiUrl, _defaultUrl);
  }

  static Future<String> _getOrDefault(
    Future<String?> Function() getter,
    String fallback,
  ) async {
    final v = await getter();
    if (v == null || v.trim().isEmpty) return fallback;
    return v.trim();
  }

  static List<int> _parseSize(String size) {
    final parts = size.split('x');
    if (parts.length == 2) {
      final w = int.tryParse(parts[0]);
      final h = int.tryParse(parts[1]);
      if (w != null && h != null) return [w, h];
    }
    return [1024, 1024];
  }

  /// Minimal txt2img workflow in ComfyUI API format.
  static Map<String, dynamic> _buildWorkflow({
    required String model,
    required String positive,
    required String negative,
    required int width,
    required int height,
    required int seed,
    int steps = 35,
    double cfg = 6,
  }) {
    return {
      '3': {
        'class_type': 'KSampler',
        'inputs': {
          'seed': seed,
          'steps': steps,
          'cfg': cfg,
          'sampler_name': 'dpmpp_2m',
          'scheduler': 'karras',
          'denoise': 1,
          'model': ['4', 0],
          'positive': ['6', 0],
          'negative': ['7', 0],
          'latent_image': ['5', 0],
        },
      },
      '4': {
        'class_type': 'CheckpointLoaderSimple',
        'inputs': {'ckpt_name': model},
      },
      '5': {
        'class_type': 'EmptyLatentImage',
        'inputs': {'width': width, 'height': height, 'batch_size': 1},
      },
      '6': {
        'class_type': 'CLIPTextEncode',
        'inputs': {'text': positive, 'clip': ['4', 1]},
      },
      '7': {
        'class_type': 'CLIPTextEncode',
        'inputs': {'text': negative, 'clip': ['4', 1]},
      },
      '8': {
        'class_type': 'VAEDecode',
        'inputs': {'samples': ['3', 0], 'vae': ['4', 2]},
      },
      '9': {
        'class_type': 'SaveImage',
        'inputs': {'filename_prefix': 'memex', 'images': ['8', 0]},
      },
    };
  }

  static Future<List<Uint8List>> _pollForImages(
    String baseUrl,
    String promptId,
  ) async {
    final deadline = DateTime.now().add(_timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(_pollInterval);
      try {
        final resp = await _dio.get(
          '$baseUrl/history/$promptId',
          options: Options(responseType: ResponseType.bytes),
        );
        final raw = resp.data as List<int>;
        final jsonStr = String.fromCharCodes(raw);
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        final entry = data[promptId] as Map<String, dynamic>?;
        if (entry == null) continue;

        final status = entry['status'] as Map<String, dynamic>?;
        final statusStr = status?['status_str'] as String? ?? '';
        if (statusStr == 'error') {
          final messages = status?['messages'] as List?;
          String errMsg = 'ComfyUI execution error';
          if (messages != null) {
            for (final m in messages) {
              if (m is List && m.isNotEmpty && m[0] == 'execution_error') {
                final info = m[1] as Map<String, dynamic>?;
                errMsg = info?['exception_message'] as String? ?? errMsg;
                break;
              }
            }
          }
          throw Exception(errMsg);
        }

        final outputs = entry['outputs'] as Map<String, dynamic>?;
        if (outputs == null) continue;
        final saveNode = outputs['9'];
        if (saveNode == null) continue;
        final imageInfos = (saveNode as Map<String, dynamic>)['images'] as List?;
        if (imageInfos == null || imageInfos.isEmpty) continue;

        final images = <Uint8List>[];
        for (final info in imageInfos) {
          if (info is! Map<String, dynamic>) continue;
          final filename = info['filename'] as String?;
          final subfolder = info['subfolder'] as String? ?? '';
          if (filename == null) continue;

          final viewUrl = '$baseUrl/view?filename=$filename'
              '${subfolder.isNotEmpty ? '&subfolder=$subfolder' : ''}'
              '&type=output';
          debugPrint('[ImageGen] ComfyUI downloading: $filename');
          final imgResp = await _dio.get(
            viewUrl,
            options: Options(responseType: ResponseType.bytes),
          );
          images.add(Uint8List.fromList(imgResp.data as List<int>));
        }
        return images;
      } catch (e) {
        debugPrint('[ImageGen] ComfyUI poll error (non-fatal): $e');
      }
    }
    throw Exception('ComfyUI generation timed out after ${_timeout.inMinutes} min');
  }
}