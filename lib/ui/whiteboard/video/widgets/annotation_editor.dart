/// Annotation editor — inline form for creating a video annotation card.
///
/// Appears when the ViewModel has a pending annotation. Shows the time range,
/// a title input, a body input, and save/cancel buttons. On save, creates
/// a time_range Anchor + Annotation Card via the ViewModel.
library;

import 'package:flutter/material.dart';

import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';
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
    final tokens = DesktopWorkspaceTokens.of(context);
    final startMs = widget.viewModel.pendingAnnotationStartMs ?? 0;

    return Container(
      key: const ValueKey('video_annotation_editor'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.divider, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with time range
          Row(
            children: [
              Icon(Icons.bookmark_outline, size: 16, color: tokens.action),
              const SizedBox(width: 6),
              Text(
                '时间标注',
                style: whiteboardUiTextStyle(
                  color: tokens.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                VideoStudyViewModel.formatTimecode(startMs),
                style: richTextCodeTextStyle(
                  color: tokens.action,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Title input
          TextField(
            controller: _titleController,
            decoration: _inputDecoration(tokens, '标题'),
            style: whiteboardUiTextStyle(
              fontSize: 14,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          // Body input
          TextField(
            controller: _bodyController,
            maxLines: 3,
            decoration: _inputDecoration(tokens, '笔记'),
            style: whiteboardUiTextStyle(
              fontSize: 14,
              height: 1.6,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          // Quote input (optional)
          TextField(
            controller: _quoteController,
            maxLines: 2,
            decoration: _inputDecoration(tokens, '引用原文（可选）'),
            style: whiteboardUiTextStyle(
              fontSize: 13,
              height: 1.5,
              color: tokens.textMuted,
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
                },
                child: Text(
                  '取消',
                  style: whiteboardUiTextStyle(color: tokens.textMuted),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: widget.viewModel.isSavingAnnotation ? null : _save,
                icon: widget.viewModel.isSavingAnnotation
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 16),
                label: Text(
                  widget.viewModel.isSavingAnnotation ? '保存中…' : '保存标注',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.action,
                  foregroundColor: tokens.canvas,
                  minimumSize: const Size(44, 44),
                  textStyle: whiteboardUiTextStyle(fontSize: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    await widget.viewModel.confirmAnnotation(
      title: _titleController.text.trim(),
      body: _bodyController.text.trim(),
      quote: _quoteController.text.trim().isEmpty
          ? null
          : _quoteController.text.trim(),
    );
  }

  InputDecoration _inputDecoration(
    DesktopWorkspaceTokens tokens,
    String label,
  ) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: tokens.divider),
    );
    return InputDecoration(
      labelText: label,
      isDense: true,
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: tokens.action, width: 1.5),
      ),
      labelStyle: whiteboardUiTextStyle(color: tokens.textMuted, fontSize: 12),
    );
  }
}
