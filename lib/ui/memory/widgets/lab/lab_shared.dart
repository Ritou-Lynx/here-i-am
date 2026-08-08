/// Shared widgets, tokens helpers and data loaders for the Memory V3 Lab
/// sub-pages.
///
/// Everything here is consumed only by `lib/ui/memory/widgets/lab/*` and the
/// Lab hub. It intentionally keeps the test-rig look consistent with the
/// 春雨昼眠 daylight tokens instead of bespoke colors.
library;

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';

/// Status kind for [LabStatusBanner].
enum LabStatusKind { error, success, info }

/// Token-styled banner showing operation results. Multi-line friendly,
/// replaces the old red/green `_LabStatusMessage`.
class LabStatusBanner extends StatelessWidget {
  const LabStatusBanner({
    super.key,
    required this.message,
    required this.kind,
    this.maxHeight = 128,
  });

  final String message;
  final LabStatusKind kind;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    final (fg, bg) = switch (kind) {
      LabStatusKind.error => (t.error, t.errorSoft),
      LabStatusKind.success => (t.success, t.successSoft),
      LabStatusKind.info => (t.info, t.infoSoft),
    };
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(t.radius10),
          border: Border.all(color: fg.withValues(alpha: 0.35)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: t.space12,
            vertical: t.space8,
          ),
          child: SelectableText(
            message,
            style: TextStyle(color: fg, fontSize: 12, height: 1.4),
          ),
        ),
      ),
    );
  }
}

/// Token-styled confirmation dialog. Returns true when the user confirms.
Future<bool> showLabConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  bool danger = false,
}) async {
  final t = context.springRainUi;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(
            foregroundColor: danger ? t.error : t.accent,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Small section label rendered with `textSecondary` + `titleSmall` weight.
class LabSectionLabel extends StatelessWidget {
  const LabSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        t.space16,
        t.space16,
        t.space16,
        t.space4,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: t.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Empty-state placeholder used inside Lab list pages.
class LabEmptyState extends StatelessWidget {
  const LabEmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    return Padding(
      padding: EdgeInsets.all(t.space32),
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: t.textTertiary, fontSize: 13),
        ),
      ),
    );
  }
}

/// Thin progress line shown at the top of a page while an operation runs.
class LabBusyLine extends StatelessWidget {
  const LabBusyLine({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    return SizedBox(
      height: 2,
      child: visible
          ? LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: t.surfaceMuted,
            )
          : const SizedBox.shrink(),
    );
  }
}

/// Navigation row used by the Lab hub. Mirrors the personal-center
/// `_DestinationRow` shape but reads from [SpringRainUiTokens] directly.
class LabNavRow extends StatelessWidget {
  const LabNavRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.status,
    this.warning = false,
    this.danger = false,
    this.diagnostic = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? status;
  final bool warning;
  final bool danger;
  final bool diagnostic;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    final enabled = onTap != null;
    final iconColor = danger
        ? t.error
        : diagnostic
            ? t.iconMuted
            : (enabled ? t.accent : t.iconMuted);
    final titleColor =
        danger ? t.error : (diagnostic ? t.textSecondary : t.textPrimary);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: EdgeInsets.symmetric(
          horizontal: t.space16,
          vertical: t.space12,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.divider)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: t.surfaceMuted,
                borderRadius: BorderRadius.circular(t.radius10),
              ),
              child: Icon(icon, size: t.iconMedium, color: iconColor),
            ),
            SizedBox(width: t.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (warning)
              Padding(
                padding: EdgeInsets.only(right: t.space4),
                child: SizedBox.square(
                  dimension: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.gold,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            if (status != null)
              Flexible(
                child: Padding(
                  padding: EdgeInsets.only(left: t.space4),
                  child: Text(
                    status!,
                    style: TextStyle(
                      color: warning ? t.warning : t.textTertiary,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            if (enabled) ...[
              SizedBox(width: t.space4),
              Icon(
                Icons.chevron_right_rounded,
                color: t.iconMuted,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shared data loaders used by multiple Lab sub-pages. Kept here so each page
/// does not reimplement the same raw Drift query.

/// Returns the character id of the most recent chat message, or null.
Future<String?> latestChatCharacterId() async {
  final db = AppDatabase.instance;
  final rows = await (db.select(db.personaChatMessages)
        ..orderBy([
          (t) => drift.OrderingTerm.desc(t.timestamp),
          (t) => drift.OrderingTerm.desc(t.id),
        ])
        ..limit(1))
      .get();
  return rows.isEmpty ? null : rows.single.characterId;
}

/// Returns the highest message id of type 'chat', or null.
Future<int?> latestChatMessageId() async {
  final db = AppDatabase.instance;
  final rows = await (db.select(db.personaChatMessages)
        ..where((t) => t.messageType.equals('chat'))
        ..orderBy([(t) => drift.OrderingTerm.desc(t.id)])
        ..limit(1))
      .get();
  return rows.isEmpty ? null : rows.single.id;
}

/// Cheap COUNT(*) for a table name.
Future<int> tableCount(String tableName) async {
  final row = await AppDatabase.instance
      .customSelect('SELECT COUNT(*) AS c FROM $tableName')
      .getSingle();
  return row.read<int>('c');
}

/// Fragment-batch watermark for [characterId].
Future<int> dreamingWatermark(String characterId) async {
  final db = AppDatabase.instance;
  final row = await (db.select(db.kvStore)
        ..where((t) =>
            t.bucket.equals('memory_v3.dreaming') &
            t.key.equals('dreaming.fragment.last_message_id.$characterId')))
      .getSingleOrNull();
  return int.tryParse(row?.value ?? '') ?? 0;
}

/// Slider for picking a fragment's emotional weight (0.0..1.0).
///
/// Stashes the last picked value in [lastPicked] so the parent dialog can
/// read it after the user taps Save.
class EmotionalWeightSlider extends StatefulWidget {
  const EmotionalWeightSlider({super.key, required this.initial});

  final double initial;

  /// Last value picked via the slider. Null if the user never moved it.
  static double? lastPicked;

  @override
  State<EmotionalWeightSlider> createState() => _EmotionalWeightSliderState();
}

class _EmotionalWeightSliderState extends State<EmotionalWeightSlider> {
  late double _value = widget.initial;

  @override
  void initState() {
    super.initState();
    EmotionalWeightSlider.lastPicked = null;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '情感权重: ${_value.toStringAsFixed(2)}',
          style: TextStyle(color: t.textSecondary, fontSize: 12),
        ),
        Slider(
          value: _value,
          min: 0,
          max: 1,
          divisions: 20,
          label: _value.toStringAsFixed(2),
          onChanged: (v) {
            setState(() => _value = v);
            EmotionalWeightSlider.lastPicked = v;
          },
        ),
      ],
    );
  }
}

/// Int slider (e.g. 1..10) for episode significance.
class IntSliderField extends StatelessWidget {
  const IntSliderField({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int min;
  final int max;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            '$label: $value',
            style: TextStyle(color: t.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: '$value',
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
      ],
    );
  }
}

/// Double slider with a fixed value range. Used for valence/arousal.
class DoubleSliderField extends StatelessWidget {
  const DoubleSliderField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            '$label: ${value.toStringAsFixed(2)}',
            style: TextStyle(color: t.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: 20,
            label: value.toStringAsFixed(2),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
