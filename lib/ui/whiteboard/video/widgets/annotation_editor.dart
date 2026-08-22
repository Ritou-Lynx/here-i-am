/// Annotation editor — inline form for creating a video annotation card.
///
/// Appears when the ViewModel has a pending annotation. Shows the time range,
/// one continuous document and save/cancel buttons. The first line projects
/// to the Card title; everything after it remains one editable Card body.
/// A cue quote may be inserted into that document, but is never a separate
/// required field and can be edited or deleted before saving.
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
  final _documentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final quote = widget.initialQuote?.trim();
    if (quote != null && quote.isNotEmpty) {
      _documentController.text = '\n\n原文引用\n$quote';
      _documentController.selection = const TextSelection.collapsed(offset: 0);
    }
  }

  @override
  void dispose() {
    _documentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final startMs = widget.viewModel.pendingAnnotationStartMs ?? 0;
    final endMs = widget.viewModel.pendingAnnotationEndMs ?? startMs;
    final timeLabel = widget.viewModel.pendingAnnotationIsPoint
        ? VideoStudyViewModel.formatTimecode(startMs)
        : '${VideoStudyViewModel.formatTimecode(startMs)}–'
            '${VideoStudyViewModel.formatTimecode(endMs)}';

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
                timeLabel,
                style: richTextCodeTextStyle(
                  color: tokens.action,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The annotation is one continuous document. Card title/body and
          // optional Anchor quote are projections produced only on save.
          TextField(
            key: const ValueKey('video_annotation_document'),
            controller: _documentController,
            minLines: 8,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: '第一行作为标题\n继续写正文；原文引用也在这里，可直接编辑或删除',
              hintStyle: whiteboardUiTextStyle(
                color: tokens.textFaint,
                fontSize: 12,
              ),
              filled: false,
              fillColor: Colors.transparent,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
            ),
            style: whiteboardUiTextStyle(
              fontSize: 14,
              height: 1.6,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          // Actions
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
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
    final projection = _AnnotationDocumentProjection.fromDocument(
      _documentController.text,
    );
    await widget.viewModel.confirmAnnotation(
      title: projection.title,
      body: projection.body,
      quote: projection.quote,
    );
  }
}

class _AnnotationDocumentProjection {
  const _AnnotationDocumentProjection({
    required this.title,
    required this.body,
    required this.quote,
  });

  final String title;
  final String body;
  final String? quote;

  factory _AnnotationDocumentProjection.fromDocument(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final title = lines.isEmpty ? '' : lines.first.trim();
    final bodyLines = lines.length <= 1 ? const <String>[] : lines.sublist(1);
    final markerIndex = bodyLines.indexWhere(
      (line) => line.trim() == '原文引用',
    );
    String? quote;
    if (markerIndex >= 0) {
      final quoteText = bodyLines
          .skip(markerIndex + 1)
          .map((line) => line.startsWith('> ') ? line.substring(2) : line)
          .join('\n')
          .trim();
      if (quoteText.isNotEmpty) quote = quoteText;
    }
    return _AnnotationDocumentProjection(
      title: title,
      body: bodyLines.join('\n').trim(),
      quote: quote,
    );
  }
}
