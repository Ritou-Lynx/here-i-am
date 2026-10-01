import 'package:flutter/material.dart';
import 'package:memex/ui/desktop/widgets/desktop_persona_chat_view.dart';
import 'package:memex/ui/p6_r7_product/view_models/p6_r7_product_chat_view_model.dart';

/// Candidate product surface containing only the normal desktop conversation.
class P6R7ProductChatSurface extends StatefulWidget {
  const P6R7ProductChatSurface({super.key, required this.viewModel});

  final P6R7ProductChatViewModel viewModel;

  @override
  State<P6R7ProductChatSurface> createState() => _P6R7ProductChatSurfaceState();
}

class _P6R7ProductChatSurfaceState extends State<P6R7ProductChatSurface> {
  late final TextEditingController _composer;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _composer = TextEditingController();
    _focusNode = FocusNode();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _composer.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final input = _composer.text;
    final submission = await widget.viewModel.sendWithAdmission(input);
    if (mounted &&
        shouldClearP6R7ProductChatDraft(
          persisted: submission.persisted,
          currentDraft: _composer.text,
          submittedText: input,
        )) {
      _composer.clear();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.viewModel,
        builder: (context, _) => DesktopPersonaChatView(
          loading: widget.viewModel.loading,
          messagesNewestFirst: widget.viewModel.messagesNewestFirst,
          isStreaming: widget.viewModel.isStreaming,
          streamingText: widget.viewModel.streamingText,
          controller: _composer,
          composerFocusNode: _focusNode,
          scrollController: _scrollController,
          onSend: _send,
          onStop: widget.viewModel.stop,
        ),
      );
}

bool shouldClearP6R7ProductChatDraft({
  required bool persisted,
  required String currentDraft,
  required String submittedText,
}) =>
    persisted && currentDraft == submittedText;
