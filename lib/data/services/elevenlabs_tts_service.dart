import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

class ElevenLabsTtsService {
  static const _baseUrl = 'https://api.elevenlabs.io';
  static const _modelId = 'eleven_v3';
  static final _log = getLogger('ElevenLabsTts');

  /// Generate speech for [text] using [voiceId]. Returns path to local audio file.
  /// Caches results by text+voiceId hash so repeated requests hit disk.
  /// Throws [Exception] with a descriptive message on failure.
  static Future<String> textToSpeech({
    required String text,
    required String voiceId,
  }) async {
    if (text.trim().isEmpty) throw Exception('Text is empty');
    final speechText = _prepareTextForSpeech(text);

    final apiKey = await UserStorage.getElevenLabsApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('ElevenLabs API Key 未配置，请在 Settings 中设置');
    }

    final cacheKey = _cacheKey(speechText, voiceId);
    final cachePath = await _cachePath(cacheKey);

    if (await File(cachePath).exists()) {
      _log.fine('TTS cache hit: $cacheKey');
      return cachePath;
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/v1/text-to-speech/$voiceId'),
      headers: {
        'xi-api-key': apiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'text': speechText,
        'model_id': _modelId,
        'voice_settings': {
          // Stability low (Creative end) lets pitch/pace/breath vary naturally
          // per the voice-test plan v1 + ELevenlabs-TTS.md guidance.
          // Style high to carry emotional intensity. Speaker boost keeps the
          // voice anchored to the base timbre without over-rigid cloning.
          'stability': 0.25,
          'similarity_boost': 0.75,
          'style': 0.84,
          'use_speaker_boost': true,
        },
      }),
    );

    if (response.statusCode == 200) {
      final file = File(cachePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);
      _log.info(
          'TTS generated: $cacheKey (${response.bodyBytes.length} bytes)');
      return cachePath;
    } else {
      String detail;
      try {
        final body = jsonDecode(response.body);
        detail = body['detail']?['message'] ?? response.body;
      } catch (_) {
        detail = response.body;
      }
      throw Exception('API 错误 ${response.statusCode}: $detail');
    }
  }

  static Stream<List<int>> streamTextToSpeech({
    required String text,
    required String voiceId,
  }) async* {
    if (text.trim().isEmpty) return;
    final speechText = _prepareTextForSpeech(text);

    final apiKey = await UserStorage.getElevenLabsApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('ElevenLabs API Key 未配置，请在 Settings 中设置');
    }

    // Disk cache: if a previous (streaming or non-streaming) request already
    // produced audio for this text+voiceId, replay the file as a stream instead
    // of burning another API call. This is the single biggest credit saver —
    // without it, voice-mode replays of the same message cost full price every
    // time. StreamSubscription.cancel() (called by StreamingTtsSession.cancel)
    // naturally stops the file read mid-stream.
    final cacheKey = _cacheKey(speechText, voiceId);
    final cachePath = await _cachePath(cacheKey);
    if (await File(cachePath).exists()) {
      _log.fine('TTS stream cache hit: $cacheKey');
      yield* File(cachePath).openRead();
      return;
    }

    final client = http.Client();
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$_baseUrl/v1/text-to-speech/$voiceId/stream'),
      );
      request.headers.addAll({
        'xi-api-key': apiKey,
        'Content-Type': 'application/json',
      });
      request.body = jsonEncode({
        'text': speechText,
        'model_id': _modelId,
        'voice_settings': {
          'stability': 0.25,
          'similarity_boost': 0.75,
          'style': 0.84,
          'use_speaker_boost': true,
        },
      });

      final response = await client.send(request);
      if (response.statusCode == 200) {
        // Tee the stream: yield bytes to the caller while simultaneously
        // writing them to the cache file for future replays.
        final file = File(cachePath);
        await file.parent.create(recursive: true);
        final sink = file.openWrite();
        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            yield chunk;
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        _log.info('TTS stream cached: $cacheKey');
      } else {
        final body = await response.stream.bytesToString();
        String detail;
        try {
          final json = jsonDecode(body);
          detail = json['detail']?['message'] ?? body;
        } catch (_) {
          detail = body;
        }
        throw Exception('API 错误 ${response.statusCode}: $detail');
      }
    } finally {
      client.close();
    }
  }

  static String _prepareTextForSpeech(String text) {
    final normalized = normalizeSpokenText(text.trim());
    if (normalized.isEmpty) return normalized;

    // Eleven v3 understands pause audio tags rather than SSML <break>. A small
    // lead-in and sentence pause prevents Chinese onsets from being swallowed
    // at generation/playback boundaries.
    var withSentencePauses = normalized.replaceAllMapped(
      RegExp(r'([。！？!?；;])\s*'),
      (match) => '${match.group(1)} [short pause] ',
    );

    // Strip a trailing [short pause] so ElevenLabs does not synthesize an
    // extra trailing breath/gasp after the final sentence. The audio ends
    // naturally at the last punctuation mark.
    withSentencePauses =
        withSentencePauses.replaceAll(RegExp(r'\s*\[short pause\]\s*$'), '');

    // If the text already opens with a TTS audio tag (e.g. [softly]),
    // prepending [short pause] would stack two tags and dilute the opening
    // emotion. Let the character's opening tag lead.
    if (RegExp(r'^\s*\[[^\]]+\]').hasMatch(withSentencePauses)) {
      return withSentencePauses.trim();
    }
    return '[short pause] $withSentencePauses'.trim();
  }

  // ── Spoken-text normalization (pitfall #26: wash digits into spoken form) ─

  static final RegExp _shortcutPattern =
      RegExp(r'\b(?:ctrl|control)\s*\+\s*([a-z])', caseSensitive: false);

  static final RegExp _latinLetter = RegExp(r'[A-Za-z]');

  /// Digits, symbols, and keyboard shortcuts are read literally (or wrongly)
  /// by the TTS engine. Convert them into natural spoken Chinese before
  /// synthesis — e.g. `391` → `三百九十一`, `2026-06-18` → `二零二六年六月十八日`,
  /// `￥39.9` → `三十九块九`, `Ctrl+C` → `复制`.
  ///
  /// Only affects the TTS request path; stored/displayed text stays untouched.
  static String normalizeSpokenText(String text) {
    var result = _normalizeShortcuts(text);
    result = result.replaceAllMapped(_spokenNumberPattern, (m) {
      // ￥/¥ amount
      if (m.group(1) != null) return _spokenMoney(m.group(1)!);
      // X元
      if (m.group(2) != null) return _spokenMoney(m.group(2)!);
      // X块 / X块钱
      if (m.group(3) != null) return _spokenMoney(m.group(3)!);
      // percent
      if (m.group(4) != null) {
        return '百分之${_spokenNumber(m.group(4)!)}';
      }
      // date (2026年6月18日 / 2026-06-18 / 2026/6/18)
      if (m.group(5) != null) {
        return '${_digitByDigit(m.group(5)!)}年'
            '${_spokenNumber(m.group(6)!)}月'
            '${_spokenNumber(m.group(7)!)}日';
      }
      // bare year
      if (m.group(8) != null) return '${_digitByDigit(m.group(8)!)}年';
      // clock time
      if (m.group(9) != null) {
        final hour = _spokenNumber(m.group(9)!);
        final minute = int.parse(m.group(10)!);
        if (minute == 0) return '$hour点';
        final minuteText = minute < 10
            ? '零${_spokenNumber('$minute')}分'
            : '${_spokenNumber('$minute')}分';
        return '$hour点$minuteText';
      }
      // fraction
      if (m.group(11) != null) {
        return '${_spokenNumber(m.group(12)!)}分之${_spokenNumber(m.group(11)!)}';
      }
      // phone number
      if (m.group(13) != null) {
        return m.group(13)!
            .split('')
            .map((c) => c == '1' ? '幺' : _speechDigits[int.parse(c)])
            .join();
      }
      // range
      if (m.group(14) != null) {
        return '${_spokenNumber(m.group(14)!)}到${_spokenNumber(m.group(15)!)}';
      }
      // decimal
      if (m.group(16) != null) {
        return _spokenNumber('${m.group(16)}.${m.group(17)}');
      }
      // plain integer
      if (m.group(18) != null) {
        // Skip numbers glued to Latin letters (v3, 5G, H2O, iPhone15…).
        final start = m.start;
        final end = m.end;
        if (start > 0 && _latinLetter.hasMatch(m.input[start - 1])) {
          return m.group(18)!;
        }
        if (end < m.input.length && _latinLetter.hasMatch(m.input[end])) {
          return m.group(18)!;
        }
        return _spokenNumber(m.group(18)!);
      }
      return m.group(0)!;
    });
    return result;
  }

  /// Ordered alternatives — specific patterns (money, date, time…) must win
  /// over plain integers.
  static final RegExp _spokenNumberPattern = RegExp(
    r'[￥¥](\d+(?:\.\d+)?)' // 1: currency symbol + amount
    r'|(\d+(?:\.\d+)?)元' // 2: amount + 元
    r'|(\d+(?:\.\d+)?)块(?:钱)?' // 3: amount + 块/块钱
    r'|(\d+(?:\.\d+)?)[%％]' // 4: percent
    r'|(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})日?' // 5,6,7: date
    r'|(\d{4})年' // 8: bare year
    r'|(\d{1,2})[：:](\d{1,2})' // 9,10: clock time
    r'|(\d+)/(\d+)' // 11,12: fraction
    r'|(1\d{10})' // 13: phone number
    r'|(\d+)-(\d+)' // 14,15: range
    r'|(\d+)\.(\d+)' // 16,17: decimal
    r'|(\d+)' // 18: integer
  );

  static const _speechDigits = [
    '零', '一', '二', '三', '四', '五', '六', '七', '八', '九',
  ];
  static const _speechUnits = ['', '十', '百', '千'];

  static String _normalizeShortcuts(String text) {
    const map = {
      'c': '复制',
      'v': '粘贴',
      'x': '剪切',
      'z': '撤销',
      's': '保存',
      'a': '全选',
      'f': '查找',
    };
    return text.replaceAllMapped(_shortcutPattern, (m) {
      final letter = m.group(1)!.toLowerCase();
      return map[letter] ?? 'control 加 ${m.group(1)!}';
    });
  }

  /// Convert a number string to spoken Chinese; ≥5 digits are read digit by
  /// digit (IDs, codes). Decimals become `X点Y`.
  static String _spokenNumber(String numStr) {
    if (numStr.contains('.')) {
      final parts = numStr.split('.');
      final intPart = parts[0].isEmpty ? '0' : parts[0];
      final fracText = parts[1]
          .split('')
          .map((c) => _speechDigits[int.parse(c)])
          .join();
      return '${_spokenInteger(int.parse(intPart))}点$fracText';
    }
    final value = int.parse(numStr);
    if (numStr.length >= 5) return _digitByDigit(numStr);
    return _spokenInteger(value);
  }

  static String _digitByDigit(String s) =>
      s.split('').map((c) => _speechDigits[int.parse(c)]).join();

  /// Integer (0–9999) to spoken Chinese: 391 → 三百九十一, 15 → 十五, 1001 → 一千零一.
  static String _spokenInteger(int value) {
    if (value == 0) return '零';
    if (value < 0) return '负${_spokenInteger(-value)}';
    final digits = value.toString();
    if (digits.length >= 5) return _digitByDigit(digits);
    final buffer = StringBuffer();
    var pendingZero = false;
    final n = digits.length;
    for (var i = 0; i < n; i++) {
      final d = int.parse(digits[i]);
      final unit = n - i - 1;
      if (d == 0) {
        if (buffer.isNotEmpty) pendingZero = true;
      } else {
        if (pendingZero) {
          buffer.write('零');
          pendingZero = false;
        }
        buffer
          ..write(_speechDigits[d])
          ..write(_speechUnits[unit]);
      }
    }
    var result = buffer.toString();
    if (result.startsWith('一十')) result = result.substring(1);
    return result;
  }

  /// Money to colloquial spoken form: 39.9 → 三十九块九, 39.99 → 三十九块九毛九,
  /// 0.5 → 五毛, 0.05 → 五分.
  static String _spokenMoney(String numStr) {
    if (!numStr.contains('.')) {
      return '${_spokenNumber(numStr)}块';
    }
    final parts = numStr.split('.');
    final intPart = parts[0];
    final fracDigits = parts[1].replaceAll(RegExp(r'0+$'), '').split('');
    if (fracDigits.isEmpty) return '${_spokenNumber(intPart)}块';
    // 0.X → X毛
    if (intPart == '0' && fracDigits.length == 1) {
      return '${_speechDigits[int.parse(fracDigits[0])]}毛';
    }
    // 0.0X → X分
    if (intPart == '0' &&
        fracDigits.length == 2 &&
        fracDigits[0] == '0') {
      return '${_speechDigits[int.parse(fracDigits[1])]}分';
    }
    if (intPart == '0') return _spokenNumber(numStr);
    if (fracDigits.length == 1) {
      return '${_spokenNumber(intPart)}块${_speechDigits[int.parse(fracDigits[0])]}';
    }
    final d0 = _speechDigits[int.parse(fracDigits[0])];
    final d1 = _speechDigits[int.parse(fracDigits[1])];
    if (fracDigits[0] == '0') {
      return '${_spokenNumber(intPart)}块零$d1分';
    }
    return '${_spokenNumber(intPart)}块$d0毛$d1';
  }

  static String _cacheKey(String text, String voiceId) {
    final bytes = utf8.encode('$_modelId:$voiceId:$text');
    return sha256.convert(bytes).toString();
  }

  static Future<String> _cachePath(String cacheKey) async {
    final dir = await FileSystemService.getAppSupportDir();
    return '${dir.path}/tts_cache/$cacheKey.mp3';
  }

  /// Remove all cached TTS audio files.
  static Future<void> clearCache() async {
    final dir = await FileSystemService.getAppSupportDir();
    final cacheDir = Directory('${dir.path}/tts_cache');
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
      _log.info('TTS cache cleared');
    }
  }
}
