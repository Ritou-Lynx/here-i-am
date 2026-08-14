/// Timeline anchor bar — a draggable progress bar that also shows
/// time anchors (point and range) overlaid on the playback timeline.
///
/// Visual: Palm deep green for progress and anchors. The timeline uses
/// Cascadia Code for time code labels. Anchors are shown as small markers
/// above the progress bar; range anchors show as a translucent green band.
library;

import 'package:flutter/material.dart';

import '../view_models/video_study_view_model.dart';

class TimelineAnchorBar extends StatelessWidget {
  final VideoStudyViewModel viewModel;

  const TimelineAnchorBar({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final duration = viewModel.durationMs;
    if (duration <= 0) return const SizedBox(height: 0);

    final position = viewModel.positionMs;
    final progress = (position / duration).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const barHeight = 24.0;

        return SizedBox(
          height: barHeight,
          child: GestureDetector(
            onTapDown: (details) {
              if (!viewModel.canSeek) return;
              final ratio = details.localPosition.dx / width;
              viewModel.seekTo((ratio * duration).toInt());
            },
            onHorizontalDragUpdate: (details) {
              if (!viewModel.canSeek) return;
              final ratio = (details.localPosition.dx / width).clamp(0.0, 1.0);
              viewModel.seekTo((ratio * duration).toInt());
            },
            child: Stack(
              children: [
                // Track
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.center,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0x55F0EFEB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                // Range anchor bands
                ...viewModel.annotations
                    .where((a) => !a.isPoint)
                    .map((a) => _RangeBand(
                          startRatio: a.startMs / duration,
                          endRatio: a.endMs / duration,
                          totalWidth: width,
                        )),
                // Progress
                Positioned(
                  left: 0,
                  top: (barHeight - 4) / 2,
                  child: Container(
                    height: 4,
                    width: width * progress,
                    decoration: BoxDecoration(
                      color: const Color(0xFF77835A),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Point anchor markers
                ...viewModel.annotations
                    .where((a) => a.isPoint)
                    .map((a) => _PointMarker(
                          ratio: a.startMs / duration,
                          totalWidth: width,
                          barHeight: barHeight,
                        )),
                // Playhead
                Positioned(
                  left: (width * progress - 6).clamp(0.0, width - 12),
                  top: (barHeight - 12) / 2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A017),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFFF2D17E), width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RangeBand extends StatelessWidget {
  final double startRatio;
  final double endRatio;
  final double totalWidth;

  const _RangeBand({
    required this.startRatio,
    required this.endRatio,
    required this.totalWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: totalWidth * startRatio,
      top: 6,
      child: Container(
        width: totalWidth * (endRatio - startRatio),
        height: 12,
        decoration: BoxDecoration(
          color: const Color(0x4443593B),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _PointMarker extends StatelessWidget {
  final double ratio;
  final double totalWidth;
  final double barHeight;

  const _PointMarker({
    required this.ratio,
    required this.totalWidth,
    required this.barHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: (totalWidth * ratio - 3).clamp(0.0, totalWidth - 6),
      top: (barHeight - 6) / 2,
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Color(0xFF43593B),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}