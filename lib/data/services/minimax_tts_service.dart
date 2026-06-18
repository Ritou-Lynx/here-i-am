import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/persona_reply_sanitizer.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

enum MiniMaxTtsScene {
  neutral,
  strictCommand,
  vulnerable,
  flirt,
}

class MiniMaxSpeechScript {
  const MiniMaxSpeechScript({
    required this.text,
    required this.scene,
    required this.speed,
    required this.vol,
    required this.pitch,
  });

  final String text;
  final MiniMaxTtsScene scene;
  final double speed;
  final double vol;
  final int pitch;

  Map<String, Object> toVoiceSetting(String voiceId) => {
        'voice_id': voiceId,
        'speed': speed,
        'vol': vol,
        'pitch': pitch,
      };

  String get cacheSignature =>
      '${scene.name}:speed=$speed:vol=$vol:pitch=$pitch:text=$text';
}

class MiniMaxTtsService {
  static const _baseUrl = 'https://api.minimax.chat';
  static const _model = 'speech-2.8-hd';
  static final _log = getLogger('MiniMaxTts');

  static const _allowedSoundTags = {
    'sniffs',
    'breath',
    'sighs',
    'laughs',
    'gasps',
    'chuckle',
    'emm',
  };

  /// Generate speech for [text] using [voiceId]. Returns path to local audio file.
  /// Caches results by text+voiceId+style hash. Throws [Exception] on failure.
  static Future<String> textToSpeech({
    required String text,
    required String voiceId,
  }) async {
    if (text.trim().isEmpty) throw Exception('Text is empty');
    final script = buildSpeechScript(text);
    if (script.text.isEmpty) throw Exception('Text is empty');

    final apiKey = await UserStorage.getMiniMaxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('MiniMax API Key is not configured in Settings');
    }
    final groupId = await UserStorage.getMiniMaxGroupId();
    if (groupId == null || groupId.isEmpty) {
      throw Exception('MiniMax Group ID is not configured in Settings');
    }

    final cacheKey = _cacheKey(script, voiceId);
    final cachePath = await _cachePath(cacheKey);

    if (await File(cachePath).exists()) {
      _log.fine('TTS cache hit: $cacheKey');
      return cachePath;
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/v1/t2a_v2?GroupId=$groupId'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'text': script.text,
        'stream': false,
        'voice_setting': script.toVoiceSetting(voiceId),
        'audio_setting': {
          'sample_rate': 32000,
          'bitrate': 128000,
          'format': 'mp3',
          'channel': 1,
        },
      }),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final statusCode = body['base_resp']?['status_code'];
      if (statusCode != 0) {
        final msg = body['base_resp']?['status_msg'] ?? 'unknown error';
        throw Exception('MiniMax API error: $msg');
      }
      // The audio field is a hex-encoded MP3 payload.
      final audioHex = body['data']?['audio'] as String?;
      if (audioHex == null || audioHex.isEmpty) {
        throw Exception('MiniMax did not return audio data');
      }
      final audioBytes = _hexDecode(audioHex);
      final file = File(cachePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(audioBytes);
      _log.info('TTS generated: $cacheKey (${audioBytes.length} bytes)');
      return cachePath;
    } else {
      String detail;
      try {
        final body = jsonDecode(response.body);
        detail = body['base_resp']?['status_msg'] ?? response.body;
      } catch (_) {
        detail = response.body;
      }
      throw Exception('MiniMax API error ${response.statusCode}: $detail');
    }
  }

  static List<int> _hexDecode(String hex) {
    final result = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  /// Builds a MiniMax-only reading script and voice style from chat text.
  ///
  /// The returned value is intentionally used only inside the TTS request path:
  /// callers keep storing and displaying the original message text.
  static MiniMaxSpeechScript buildSpeechScript(String text) {
    final spoken = PersonaReplySanitizer.spokenTextOnly(text);
    var speechText = _stripSpeechOnlyMarkup(spoken);
    if (speechText.isEmpty) {
      return const MiniMaxSpeechScript(
        text: '',
        scene: MiniMaxTtsScene.neutral,
        speed: 0.94,
        vol: 1.0,
        pitch: 0,
      );
    }

    final scene = _detectScene(speechText);
    speechText = _normalizeWhitespace(speechText);
    speechText = _normalizeSoundTags(speechText);
    speechText = _insertMiniMaxPauses(speechText, scene);
    speechText = _applySceneSoundEvent(speechText, scene);
    speechText =
        '<#0.20#> ${speechText.trim()}'.replaceAll(RegExp(r'\s+'), ' ').trim();

    final setting = _voiceSettingForScene(scene);
    return MiniMaxSpeechScript(
      text: speechText,
      scene: scene,
      speed: setting.speed,
      vol: setting.vol,
      pitch: setting.pitch,
    );
  }

  static String prepareTextForSpeech(String text) =>
      buildSpeechScript(text).text;

  static String _stripSpeechOnlyMarkup(String text) {
    return text
        .replaceAll(RegExp(r'\*{1,3}|_{1,3}'), '')
        .replaceAll(RegExp(r'`+'), '')
        .replaceAll(RegExp(r'^\s*>\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
        .replaceAll(RegExp(r'<#\d+(?:\.\d+)?#>'), '')
        .replaceAll(RegExp(r'\[[^\]\r\n]{0,40}\]'), '')
        .replaceAll(RegExp('\u3010[^\u3011\r\n]{0,40}\u3011'), '')
        .replaceAll(RegExp('\uff08[^\uff09\r\n]{0,40}\uff09'), '')
        .trim();
  }

  static String _normalizeWhitespace(String text) {
    return text
        .replaceAll(RegExp(r'\s*\r?\n+\s*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _normalizeSoundTags(String text) {
    var usedTag = false;
    return text
        .replaceAllMapped(
          RegExp(r'\(([^)\r\n]{1,40})\)'),
          (match) {
            final raw = match.group(1)!.trim();
            final tag = raw.toLowerCase();
            if (_allowedSoundTags.contains(tag) && !usedTag) {
              usedTag = true;
              return '($tag)';
            }
            return '';
          },
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static MiniMaxTtsScene _detectScene(String text) {
    final lower = text.toLowerCase();
    if (_matchesAny(lower, _strictCommandPatterns)) {
      return MiniMaxTtsScene.strictCommand;
    }
    if (_matchesAny(lower, _vulnerablePatterns)) {
      return MiniMaxTtsScene.vulnerable;
    }
    if (_matchesAny(lower, _flirtPatterns)) {
      return MiniMaxTtsScene.flirt;
    }
    return MiniMaxTtsScene.neutral;
  }

  static bool _matchesAny(String text, List<RegExp> patterns) {
    return patterns.any((pattern) => pattern.hasMatch(text));
  }

  static final _strictCommandPatterns = <RegExp>[
    RegExp(r'\bstop\b'),
    RegExp(r'\bput (?:the )?phone down\b'),
    RegExp(r'\bnot (?:asking|negotiating)\b'),
    RegExp(r'\blisten (?:to me|carefully|closely)\b'),
    RegExp(r'\bgo to sleep\b'),
    RegExp(r'\bturn (?:off|out) (?:the )?(?:screen|light|lights)\b'),
    RegExp('\u505c\u4e0b'),
    RegExp('\u4e0d\u53ef\u4ee5'),
    RegExp('\u4e0d\u662f\u5728\u8ddf\u4f60\u5546\u91cf'),
    RegExp('\u542c\u6e05\u695a'),
    RegExp('\u624b\u673a\u653e\u4e0b'),
    RegExp('\u5173\u6389\u5c4f\u5e55|\u5173\u5c4f|\u5173\u706f'),
    RegExp('\u53bb\u7761\u89c9|\u8eba\u597d'),
  ];

  static final _vulnerablePatterns = <RegExp>[
    RegExp(r'\b(sniffs|crying|scared|afraid|hurt|miss you|waited so long)\b'),
    RegExp(r"\bdon't laugh\b"),
    RegExp(r"\byou don't want me\b"),
    RegExp('\u59d4\u5c48|\u96be\u53d7|\u5bb3\u6015|\u6015\u4f60'),
    RegExp('\u54ed|\u62bd\u6ce3|\u9f3b\u5b50\u9178'),
    RegExp('\u7b49\u4e86\u4f60\u597d\u4e45|\u597d\u60f3\u4f60'),
    RegExp('\u4e0d\u60f3\u7406\u6211|\u4e0d\u60f3\u8981\u6211'),
    RegExp('\u522b\u7b11\u6211'),
  ];

  static final _flirtPatterns = <RegExp>[
    RegExp(r'\bcome closer\b'),
    RegExp(r'\bcloser\b'),
    RegExp(r'\bkiss\b'),
    RegExp(r'\bflirt\b'),
    RegExp(r'\bjust one more\b'),
    RegExp(r"\bdon't hide\b"),
    RegExp('\u8fc7\u6765\u4e00\u70b9|\u518d\u8fd1\u4e00\u70b9'),
    RegExp('\u522b\u8eb2|\u8033\u8fb9|\u9760\u8fc7\u6765'),
    RegExp('\u559c\u6b22|\u60f3\u542c\u4f60|\u53eb\u6211\u4e00\u58f0'),
    RegExp('\u66a7\u6627|\u8c03\u60c5|\u4eb2\u4e00\u4e0b'),
  ];

  static String _insertMiniMaxPauses(String text, MiniMaxTtsScene scene) {
    final ellipsisPause = switch (scene) {
      MiniMaxTtsScene.strictCommand => '0.30',
      MiniMaxTtsScene.vulnerable => '0.60',
      MiniMaxTtsScene.flirt => '0.50',
      MiniMaxTtsScene.neutral => '0.45',
    };
    final sentencePause = switch (scene) {
      MiniMaxTtsScene.strictCommand => '0.35',
      MiniMaxTtsScene.vulnerable => '0.50',
      MiniMaxTtsScene.flirt => '0.45',
      MiniMaxTtsScene.neutral => '0.42',
    };
    final commaPause = switch (scene) {
      MiniMaxTtsScene.strictCommand => '0.25',
      MiniMaxTtsScene.vulnerable => '0.36',
      MiniMaxTtsScene.flirt => '0.35',
      MiniMaxTtsScene.neutral => '0.24',
    };

    var result = text;
    result = result.replaceAllMapped(
      RegExp('(\\.{3,}|\u2026+)\\s*'),
      (match) => '${match.group(1)} <#$ellipsisPause#> ',
    );
    result = result.replaceAllMapped(
      RegExp(r'(^|[^.\d])\.(?![.\d])\s*'),
      (match) => '${match.group(1)}. <#$sentencePause#> ',
    );
    result = result.replaceAllMapped(
      RegExp('([\\u3002\\uff01\\uff1f!?])\\s*'),
      (match) => '${match.group(1)} <#$sentencePause#> ',
    );
    result = result.replaceAllMapped(
      RegExp('([,;:\\u3001\\uff0c\\uff1b\\uff1a])\\s*'),
      (match) => '${match.group(1)} <#$commaPause#> ',
    );
    return result.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _applySceneSoundEvent(String text, MiniMaxTtsScene scene) {
    if (_containsAllowedSoundTag(text)) return text;
    return switch (scene) {
      MiniMaxTtsScene.vulnerable => '(sniffs) $text',
      MiniMaxTtsScene.flirt => '(breath) $text',
      MiniMaxTtsScene.strictCommand || MiniMaxTtsScene.neutral => text,
    };
  }

  static bool _containsAllowedSoundTag(String text) {
    return RegExp(
      r'\((sniffs|breath|sighs|laughs|gasps|chuckle|emm)\)',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static MiniMaxSpeechScript _voiceSettingForScene(MiniMaxTtsScene scene) {
    return switch (scene) {
      MiniMaxTtsScene.strictCommand => const MiniMaxSpeechScript(
          text: '',
          scene: MiniMaxTtsScene.strictCommand,
          speed: 0.82,
          vol: 1.0,
          pitch: -4,
        ),
      MiniMaxTtsScene.vulnerable => const MiniMaxSpeechScript(
          text: '',
          scene: MiniMaxTtsScene.vulnerable,
          speed: 0.70,
          vol: 0.82,
          pitch: 2,
        ),
      MiniMaxTtsScene.flirt => const MiniMaxSpeechScript(
          text: '',
          scene: MiniMaxTtsScene.flirt,
          speed: 0.76,
          vol: 0.78,
          pitch: 1,
        ),
      MiniMaxTtsScene.neutral => const MiniMaxSpeechScript(
          text: '',
          scene: MiniMaxTtsScene.neutral,
          speed: 0.94,
          vol: 1.0,
          pitch: 0,
        ),
    };
  }

  static String _cacheKey(MiniMaxSpeechScript script, String voiceId) {
    final bytes = utf8.encode('$_model:$voiceId:${script.cacheSignature}');
    return sha256.convert(bytes).toString();
  }

  static Future<String> _cachePath(String cacheKey) async {
    final dir = await FileSystemService.getAppSupportDir();
    return '${dir.path}/tts_cache_minimax/$cacheKey.mp3';
  }

  static Future<void> clearCache() async {
    final dir = await FileSystemService.getAppSupportDir();
    final cacheDir = Directory('${dir.path}/tts_cache_minimax');
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
      _log.info('TTS cache cleared');
    }
  }
}
