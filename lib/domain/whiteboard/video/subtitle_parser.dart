/// Subtitle / caption parser for SRT and WebVTT formats.
///
/// Converts raw SRT or WebVTT text into a [TimedTextTrack] with cues.
/// Both formats share a similar structure: time-stamped text blocks
/// separated by blank lines. The parser is tolerant of BOM, CRLF, and
/// minor formatting deviations.
///
/// When parsing fails or the file is empty, the caller receives a track
/// with [TimedTextReliability.unavailable] so the UI can show "需要字幕".
library;

import '../player_adapter.dart';

/// Result of parsing a subtitle file.
class SubtitleParseResult {
  final TimedTextTrack? track;
  final String? error;

  const SubtitleParseResult({this.track, this.error});

  bool get isSuccess => track != null && error == null;
}

/// Parses SRT or WebVTT content into a [TimedTextTrack].
class SubtitleParser {
  SubtitleParser._();

  /// Parses raw subtitle text, auto-detecting SRT vs WebVTT.
  ///
  /// [sourceId] and [sourceVersionId] identify the video source.
  /// [language] defaults to 'zh'.
  static SubtitleParseResult parse(
    String raw, {
    required String sourceId,
    String? sourceVersionId,
    String language = 'zh',
    TimedTextSourceKind sourceKind = TimedTextSourceKind.userImport,
  }) {
    if (raw.trim().isEmpty) {
      return const SubtitleParseResult(
        error: '字幕内容为空',
      );
    }

    final text = _stripBom(raw).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final isVtt = text.trimLeft().startsWith('WEBVTT');

    final cues = isVtt
        ? _parseVttCues(text, sourceId)
        : _parseSrtCues(text, sourceId);

    if (cues.isEmpty) {
      return SubtitleParseResult(
        track: TimedTextTrack(
          trackId: 'track_${sourceId}_import',
          sourceId: sourceId,
          sourceVersionId: sourceVersionId,
          sourceKind: sourceKind,
          language: language,
          format: isVtt ? 'vtt' : 'srt',
          reliability: TimedTextReliability.partial,
          cues: const [],
        ),
        error: '未能解析出任何字幕条目',
      );
    }

    final sortedCues = cues
      ..sort((a, b) => a.startMs.compareTo(b.startMs));

    return SubtitleParseResult(
      track: TimedTextTrack(
        trackId: 'track_${sourceId}_import',
        sourceId: sourceId,
        sourceVersionId: sourceVersionId,
        sourceKind: sourceKind,
        language: language,
        format: isVtt ? 'vtt' : 'srt',
        reliability: TimedTextReliability.reliable,
        cues: sortedCues,
      ),
    );
  }

  static String _stripBom(String s) {
    if (s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF) {
      return s.substring(1);
    }
    return s;
  }

  static List<TimedTextCue> _parseSrtCues(String text, String sourceId) {
    final cues = <TimedTextCue>[];
    final blocks = text.split(RegExp(r'\n\s*\n'));

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 2) continue;

      // First line might be an index number; skip it if it's purely digits.
      int lineIdx = 0;
      if (RegExp(r'^\d+$').hasMatch(lines[0].trim())) {
        lineIdx = 1;
      }

      if (lineIdx >= lines.length) continue;
      final timeLine = lines[lineIdx];
      final timeMatch = _srtTimePattern.firstMatch(timeLine);
      if (timeMatch == null) continue;

      final startMs = _parseSrtTime(timeMatch.group(1)!);
      final endMs = _parseSrtTime(timeMatch.group(2)!);
      if (startMs == null || endMs == null) continue;

      final textLines = lines.sublist(lineIdx + 1);
      final cueText = textLines.join('\n').trim();
      if (cueText.isEmpty) continue;

      cues.add(TimedTextCue(
        cueId: 'cue_${sourceId}_${cues.length}',
        startMs: startMs,
        endMs: endMs,
        text: _stripVttCueTags(cueText),
      ));
    }

    return cues;
  }

  static List<TimedTextCue> _parseVttCues(String text, String sourceId) {
    final cues = <TimedTextCue>[];
    // Remove WEBVTT header block up to first blank line.
    final headerEnd = text.indexOf('\n\n');
    final body = headerEnd >= 0 ? text.substring(headerEnd + 2) : text;

    final blocks = body.split(RegExp(r'\n\s*\n'));

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.isEmpty) continue;

      // Optional cue identifier line (not a timestamp).
      int lineIdx = 0;
      if (!_vttTimePattern.hasMatch(lines[0])) {
        // Check if second line is a timestamp.
        if (lines.length > 1 && _vttTimePattern.hasMatch(lines[1])) {
          lineIdx = 1;
        } else {
          continue;
        }
      }

      final timeLine = lines[lineIdx];
      final timeMatch = _vttTimePattern.firstMatch(timeLine);
      if (timeMatch == null) continue;

      final startMs = _parseVttTime(timeMatch.group(1)!);
      final endMs = _parseVttTime(timeMatch.group(2)!);
      if (startMs == null || endMs == null) continue;

      final textLines = lines.sublist(lineIdx + 1);
      final cueText = textLines.join('\n').trim();
      if (cueText.isEmpty) continue;

      cues.add(TimedTextCue(
        cueId: 'cue_${sourceId}_${cues.length}',
        startMs: startMs,
        endMs: endMs,
        text: _stripVttCueTags(cueText),
      ));
    }

    return cues;
  }

  /// Strips WebVTT cue payload tags like <c>, <i>, <b>, <v>, timestamps.
  static String _stripVttCueTags(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\{[^}]+\}'), '')
        .trim();
  }

  static int? _parseSrtTime(String s) {
    // HH:MM:SS,mmm
    final m = RegExp(r'(\d{2}):(\d{2}):(\d{2})[,.](\d{3})').firstMatch(s);
    if (m == null) return null;
    return _toMs(m.group(1)!, m.group(2)!, m.group(3)!, m.group(4)!);
  }

  static int? _parseVttTime(String s) {
    // MM:SS.mmm or HH:MM:SS.mmm
    final m1 = RegExp(r'(\d{2}):(\d{2}):(\d{2})[.](\d{3})').firstMatch(s);
    if (m1 != null) {
      return _toMs(m1.group(1)!, m1.group(2)!, m1.group(3)!, m1.group(4)!);
    }
    final m2 = RegExp(r'(\d{2}):(\d{2})[.](\d{3})').firstMatch(s);
    if (m2 != null) {
      return _toMs('0', m2.group(1)!, m2.group(2)!, m2.group(3)!);
    }
    // SRT-style comma separator also tolerated.
    return _parseSrtTime(s);
  }

  static int _toMs(String h, String m, String s, String ms) {
    return (int.parse(h) * 3600000) +
        (int.parse(m) * 60000) +
        (int.parse(s) * 1000) +
        int.parse(ms);
  }

  static final _srtTimePattern =
      RegExp(r'(\d{2}:\d{2}:\d{2}[,.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,.]\d{3})');
  static final _vttTimePattern =
      RegExp(r'((?:\d{2}:)?\d{2}:\d{2}[.]\d{3})\s*-->\s*((?:\d{2}:)?\d{2}:\d{2}[.]\d{3})');
}