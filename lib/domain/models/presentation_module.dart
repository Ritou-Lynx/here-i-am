import 'dart:convert';

/// Block-based presentation model for a Memory Summary Card.
///
/// A [PresentationModule] is rendered as the visible content of one Memory
/// Summary Card. Each [MemoryBlock] corresponds to one activity panel in the
/// design (text, quote, number, table, ...). The card shell (mood color, foot
/// tags, status pill, "聊聊" button) is derived from the entity row itself
/// (valence/arousal/tags/status), not from this module.
class PresentationModule {
  const PresentationModule({
    required this.blocks,
    this.title,
    this.subjectRef,
    this.statusLabel,
  });

  /// Optional title shown above the blocks (e.g., "睡眠", "牙科复诊").
  final String? title;

  /// Optional short subject reference shown above the first block, e.g.
  /// "妈妈 · 通话中" or "沙丘 · 第一部".
  final String? subjectRef;

  /// Optional status pill text shown at the corner of the card, e.g.
  /// "待确认" / "需复核". Distinct from entity.status (active/completed/cancelled).
  final String? statusLabel;

  final List<MemoryBlock> blocks;

  bool get isEmpty => blocks.isEmpty && (title?.isEmpty ?? true);

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (subjectRef != null) 'subjectRef': subjectRef,
        if (statusLabel != null) 'statusLabel': statusLabel,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  String toJsonString() => jsonEncode(toJson());

  static PresentationModule? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  static PresentationModule fromJson(Map<String, dynamic> json) {
    final rawBlocks = json['blocks'];
    final blocks = <MemoryBlock>[];
    if (rawBlocks is List) {
      for (final item in rawBlocks) {
        if (item is! Map) continue;
        final block = MemoryBlock.tryFromJson(Map<String, dynamic>.from(item));
        if (block != null) blocks.add(block);
      }
    }
    return PresentationModule(
      title: _string(json['title']),
      subjectRef: _string(json['subjectRef']),
      statusLabel: _string(json['statusLabel']),
      blocks: blocks,
    );
  }
}

/// Base class for activity panels in a [PresentationModule].
abstract class MemoryBlock {
  const MemoryBlock();

  String get type;

  Map<String, dynamic> toJson();

  static MemoryBlock? tryFromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString() ?? json['kind']?.toString();
    switch (type) {
      case TextBlock.kType:
        return TextBlock.fromJson(json);
      case QuoteBlock.kType:
        return QuoteBlock.fromJson(json);
      case NumberBlock.kType:
        return NumberBlock.fromJson(json);
      case TableBlock.kType:
        return TableBlock.fromJson(json);
      case SparklineBlock.kType:
        return SparklineBlock.fromJson(json);
      case MediaBlock.kType:
        return MediaBlock.fromJson(json);
      case LinkAttachmentBlock.kType:
        return LinkAttachmentBlock.fromJson(json);
      case ProgressBarBlock.kType:
        return ProgressBarBlock.fromJson(json);
      default:
        return null;
    }
  }
}

/// A short prose paragraph. May contain inline emphasized spans (rendered with
/// a soft underline / accent color).
class TextBlock extends MemoryBlock {
  const TextBlock({required this.text, this.emphases = const []});

  static const kType = 'text';

  final String text;

  /// Substrings of [text] that should be visually emphasized. Stored as plain
  /// substrings so reformatting stays robust if the text is edited later.
  final List<String> emphases;

  @override
  String get type => kType;

  @override
  Map<String, dynamic> toJson() => {
        'type': kType,
        'text': text,
        if (emphases.isNotEmpty) 'emphases': emphases,
      };

  static TextBlock fromJson(Map<String, dynamic> json) => TextBlock(
        text: _string(json['text']) ?? '',
        emphases: _stringList(json['emphases']),
      );
}

/// A quoted line (someone else's words, or a salient self-said line) with an
/// optional contextual note underneath.
class QuoteBlock extends MemoryBlock {
  const QuoteBlock({required this.text, this.context});

  static const kType = 'quote';

  final String text;
  final String? context;

  @override
  String get type => kType;

  @override
  Map<String, dynamic> toJson() => {
        'type': kType,
        'text': text,
        if (context != null) 'context': context,
      };

  static QuoteBlock fromJson(Map<String, dynamic> json) => QuoteBlock(
        text: _string(json['text']) ?? '',
        context: _string(json['context']),
      );
}

/// A prominent number with optional unit and explanatory note.
class NumberBlock extends MemoryBlock {
  const NumberBlock({
    required this.value,
    this.unit,
    this.note,
  });

  static const kType = 'number';

  final String value;
  final String? unit;
  final String? note;

  @override
  String get type => kType;

  @override
  Map<String, dynamic> toJson() => {
        'type': kType,
        'value': value,
        if (unit != null) 'unit': unit,
        if (note != null) 'note': note,
      };

  static NumberBlock fromJson(Map<String, dynamic> json) => NumberBlock(
        value: _string(json['value']) ?? '',
        unit: _string(json['unit']),
        // `caption` was used by the Record Organizer prompt before the Dart
        // model settled on `note`. Keep accepting it so existing cards do not
        // silently lose their explanation.
        note: _string(json['note']) ?? _string(json['caption']),
      );
}

/// A two-column key/value table for plans, schedules, splits, etc.
class TableBlock extends MemoryBlock {
  const TableBlock({required this.rows});

  static const kType = 'table';

  final List<TableRowData> rows;

  @override
  String get type => kType;

  @override
  Map<String, dynamic> toJson() => {
        'type': kType,
        'rows': rows.map((r) => r.toJson()).toList(),
      };

  static TableBlock fromJson(Map<String, dynamic> json) {
    final raw = json['rows'];
    final headers = _stringList(json['headers']);
    final rows = <TableRowData>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          rows.add(TableRowData.fromJson(Map<String, dynamic>.from(item)));
          continue;
        }
        // Compatibility for the early prompt shape:
        // {"headers":["项目","金额"],"rows":[["午餐","83元"]]}.
        // The UI is intentionally a compact two-column table, so additional
        // cells are folded into the value rather than discarded.
        if (item is List && item.isNotEmpty) {
          final cells = item.map(_string).whereType<String>().toList();
          if (cells.isEmpty) continue;
          final valueParts = <String>[];
          for (var i = 1; i < cells.length; i++) {
            if (cells.length > 2 && i < headers.length) {
              valueParts.add('${headers[i]}：${cells[i]}');
            } else {
              valueParts.add(cells[i]);
            }
          }
          rows.add(TableRowData(
            label: cells.first,
            value: valueParts.join(' · '),
          ));
        }
      }
    }
    return TableBlock(rows: rows);
  }
}

class TableRowData {
  const TableRowData({required this.label, required this.value});

  final String label;
  final String value;

  Map<String, dynamic> toJson() => {'label': label, 'value': value};

  static TableRowData fromJson(Map<String, dynamic> json) => TableRowData(
        label: _string(json['label']) ?? '',
        value: _string(json['value']) ?? '',
      );
}

/// A miniature trend line. Points are domain-specific values (sleep hours,
/// spend amounts, ...). Rendering normalizes them automatically.
class SparklineBlock extends MemoryBlock {
  const SparklineBlock({required this.points, this.caption});

  static const kType = 'sparkline';

  final List<double> points;
  final String? caption;

  @override
  String get type => kType;

  @override
  Map<String, dynamic> toJson() => {
        'type': kType,
        'points': points,
        if (caption != null) 'caption': caption,
      };

  static SparklineBlock fromJson(Map<String, dynamic> json) {
    final raw = json['points'];
    final points = <double>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is num) points.add(item.toDouble());
      }
    }
    return SparklineBlock(
      points: points,
      caption: _string(json['caption']),
    );
  }
}

/// An image / screenshot / audio thumbnail.
class MediaBlock extends MemoryBlock {
  const MediaBlock({
    required this.assetPath,
    this.caption,
    this.kind = 'image',
  });

  static const kType = 'media';

  final String assetPath;
  final String? caption;

  /// "image" | "audio" | "video".
  final String kind;

  @override
  String get type => kType;

  @override
  Map<String, dynamic> toJson() => {
        'type': kType,
        'assetPath': assetPath,
        'kind': kind,
        if (caption != null) 'caption': caption,
      };

  static MediaBlock fromJson(Map<String, dynamic> json) => MediaBlock(
        assetPath: _string(json['assetPath']) ?? '',
        caption: _string(json['caption']),
        kind: _string(json['kind']) ?? 'image',
      );
}

/// External link reference (Xiaohongshu post, WeChat article, ...). Rendered
/// as a compact pill with source icon + title.
class LinkAttachmentBlock extends MemoryBlock {
  const LinkAttachmentBlock({
    required this.url,
    this.title,
    this.source,
  });

  static const kType = 'linkAttachment';

  final String url;
  final String? title;

  /// Short source identifier: "xhs" | "wechat" | "dianping" | "web".
  final String? source;

  @override
  String get type => kType;

  @override
  Map<String, dynamic> toJson() => {
        'type': kType,
        'url': url,
        if (title != null) 'title': title,
        if (source != null) 'source': source,
      };

  static LinkAttachmentBlock fromJson(Map<String, dynamic> json) =>
      LinkAttachmentBlock(
        url: _string(json['url']) ?? '',
        title: _string(json['title']),
        source: _string(json['source']),
      );
}

/// Progress toward a goal: weight target, savings goal, weekly habit count,
/// reading position, etc. Rendered as a horizontal bar + "value/max unit" text.
class ProgressBarBlock extends MemoryBlock {
  const ProgressBarBlock({
    required this.value,
    required this.max,
    this.unit,
    this.label,
  });

  static const kType = 'progressBar';

  final double value;
  final double max;

  /// Optional unit string ("kg" / "次" / "页" / "¥"). Shown alongside numbers.
  final String? unit;

  /// Optional short label above the bar ("减肥目标" / "本周跑步" / "存款").
  final String? label;

  /// Clamped 0..1 progress fraction. Returns 0 when [max] is non-positive.
  double get fraction {
    if (max <= 0) return 0;
    final f = value / max;
    if (f.isNaN || f.isInfinite) return 0;
    return f.clamp(0.0, 1.0);
  }

  @override
  String get type => kType;

  @override
  Map<String, dynamic> toJson() => {
        'type': kType,
        'value': value,
        'max': max,
        if (unit != null) 'unit': unit,
        if (label != null) 'label': label,
      };

  static ProgressBarBlock fromJson(Map<String, dynamic> json) {
    double parseNum(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0;
      return 0;
    }

    final value = parseNum(json['value']);
    final hasExplicitMax = json.containsKey('max') && json['max'] != null;
    final max =
        hasExplicitMax ? parseNum(json['max']) : (value <= 1 ? 1.0 : 100.0);
    return ProgressBarBlock(
      value: value,
      // Early cards stored a ratio such as 0.6 without `max`; treating that as
      // 0.6/1 keeps the intended 60% progress instead of rendering an empty bar.
      max: max,
      unit: _string(json['unit']),
      label: _string(json['label']),
    );
  }
}

String? _string(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}
