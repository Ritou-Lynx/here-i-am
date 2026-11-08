import 'package:flutter/material.dart';

String formatCallClock(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 1 << 31);
  final s = (seconds % 60).toString().padLeft(2, '0');
  final m = ((seconds ~/ 60) % 60).toString().padLeft(2, '0');
  if (seconds >= 3600) return '${seconds ~/ 3600}:$m:$s';
  return '$m:$s';
}

String formatRemainingCallTime(Duration duration) =>
    formatCallClock(duration.isNegative ? Duration.zero : duration);

String formatCallEndSummary(Duration duration, String reason) =>
    '通话结束 · ${duration.inSeconds ~/ 60} 分 ${duration.inSeconds % 60} 秒 · $reason';

class CallNudgeBanner extends StatelessWidget {
  const CallNudgeBanner({super.key, required this.name, this.remaining});

  final String name;
  final Duration? remaining;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        _Pill(text: '$name来电 · 催睡'),
        if (remaining != null)
          _Pill(text: '剩 ${formatRemainingCallTime(remaining!)}'),
      ],
    );
  }
}

class CallEndCard extends StatelessWidget {
  const CallEndCard({
    super.key,
    required this.duration,
    required this.reason,
    required this.onTap,
  });

  final Duration duration;
  final String reason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            color: const Color(0xE8322C28),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            formatCallEndSummary(duration, reason),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class CallFailureCard extends StatelessWidget {
  const CallFailureCard({
    super.key,
    required this.reason,
    required this.onRetry,
    required this.onBack,
  });

  final String reason;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xE8322C28),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '没接通',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, height: 1.4),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(onPressed: onBack, child: const Text('返回')),
                const SizedBox(width: 12),
                FilledButton(onPressed: onRetry, child: const Text('重拨')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
    );
  }
}
