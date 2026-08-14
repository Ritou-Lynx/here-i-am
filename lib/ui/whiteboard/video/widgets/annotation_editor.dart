/// Annotation editor — inline form for creating a video annotation card.
///
/// Appears when the ViewModel has a pending annotation. Shows the time range,
/// a title input, a body input, and save/cancel buttons. On save, creates
/// a time_range Anchor + Annotation Card via the ViewModel.
library;

import 'package:flutter/material.dart';

import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import '../view_models/video_study_view_model.dart';

class AnnotationEditor extends StatefulWidget {
  final VideoStudyViewModel viewModel;
  final String? initialQuote;

  const AnnotationEditor({
    super.key,
    required this.viewModel,
    this.initialQuote,
  });

  @override
  State<AnnotationEditor> createState() => _AnnotationEditorState();
}

class _AnnotationEditorState extends State<AnnotationEditor> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _quoteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _quoteController.text = widget.initialQuote ?? '';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _quoteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startMs = widget.viewModel.pendingAnnotationStartMs ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpringRainUiTokens.daylightSurfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0x4043593B),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with time range
          Row(
            children: [
              const Icon(
                Icons.bookmark,
                size: 16,
                color: Color(0xFF43593B),
              ),
              const SizedBox(width: 6),
              Text(
                '时间标注',
                style: TextStyle(
                  color: SpringRainUiTokens.daylightTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                VideoStudyViewModel.formatTimecode(startMs),
                style: const TextStyle(
                  color: Color(0xFF43593B),
                  fontSize: 13,
                  fontFamily: 'Cascadia Code',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Title input
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: '标题',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            style: TextStyle(
              fontSize: 14,
              color: SpringRainUiTokens.daylightTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          // Body input
          TextField(
            controller: _bodyController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '笔记',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: SpringRainUiTokens.daylightTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          // Quote input (optional)
          TextField(
            controller: _quoteController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '引用原文（可选）',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: SpringRainUiTokens.daylightTextSecondary,
            ),
          ),
          const SizedBox(height: 12),
          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  widget.viewModel.cancelAnnotation();
                  Navigator.of(context).maybePop();
                },
                child: Text(
                  '取消',
                  style: TextStyle(
                    color: SpringRainUiTokens.daylightTextSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('保存标注'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF43593B),
                  foregroundColor: const Color(0xFFF0EFEB),
                  textStyle: const TextStyle(fontSize: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _save() {
    widget.viewModel.confirmAnnotation(
      title: _titleController.text.trim(),
      body: _bodyController.text.trim(),
      quote: _quoteController.text.trim().isEmpty
          ? null
          : _quoteController.text.trim(),
    );
  }
}