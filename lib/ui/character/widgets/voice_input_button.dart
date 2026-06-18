import 'package:flutter/material.dart';
import 'package:memex/data/services/asr/voice_input_controller.dart';

/// Microphone button bound to a [VoiceInputController].
///
/// Visual states:
///   idle       — outlined mic icon
///   recording  — filled mic icon with red pulse halo
///   processing — small spinner
class VoiceInputButton extends StatelessWidget {
  const VoiceInputButton({
    super.key,
    required this.controller,
    required this.onTap,
    required this.iconColor,
    required this.bgColor,
    this.size = 40,
    this.enabled = true,
  });

  final VoiceInputController controller;

  /// Called on tap. Parent is expected to invoke [controller.toggle] inside
  /// and act on its return value (recognized text or null).
  final VoidCallback onTap;

  final Color iconColor;
  final Color bgColor;
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        final isRecording = state == VoiceInputState.recording;
        final isProcessing = state == VoiceInputState.processing;

        Widget inner;
        if (isProcessing) {
          inner = SizedBox(
            width: size * 0.45,
            height: size * 0.45,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(iconColor),
            ),
          );
        } else {
          inner = Icon(
            isRecording ? Icons.mic : Icons.mic_none,
            size: size * 0.5,
            color: isRecording ? Colors.white : iconColor,
          );
        }

        return Semantics(
          button: true,
          enabled: enabled && !isProcessing,
          label: isRecording ? 'Stop voice input' : 'Start voice input',
          child: GestureDetector(
            onTap: enabled && !isProcessing ? onTap : null,
            child: Opacity(
              opacity: enabled ? 1 : 0.45,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: isRecording ? Colors.redAccent.shade400 : bgColor,
                  shape: BoxShape.circle,
                  boxShadow: isRecording
                      ? [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.6),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: inner,
              ),
            ),
          ),
        );
      },
    );
  }
}
