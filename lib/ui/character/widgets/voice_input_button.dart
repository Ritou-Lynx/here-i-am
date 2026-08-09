import 'dart:ui';

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
    this.isMuted = false,
    this.isCallMode = false,
  });

  final VoiceInputController controller;

  /// Called on tap. Parent is expected to invoke [controller.toggle] inside
  /// and act on its return value (recognized text or null).
  final VoidCallback onTap;

  final Color iconColor;
  final Color bgColor;
  final double size;
  final bool enabled;
  final bool isMuted;
  final bool isCallMode;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        final isRecording = state == VoiceInputState.recording && !isMuted;
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
            isMuted
                ? Icons.mic_off_rounded
                : (isRecording ? Icons.mic : Icons.mic_none),
            size: size * 0.5,
            color: isRecording
                ? Colors.white
                : (isMuted ? const Color(0xFFFFC6B5) : iconColor),
          );
        }

        return Semantics(
          button: true,
          enabled: enabled && !isProcessing,
          label: isCallMode
              ? (isMuted ? 'Unmute microphone' : 'Mute microphone')
              : (isRecording ? 'Stop voice input' : 'Start voice input'),
          child: GestureDetector(
            onTap: enabled && !isProcessing ? onTap : null,
            child: Opacity(
              opacity: enabled ? 1 : 0.45,
              child: ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: bgColor,
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.34, -0.42),
                        radius: 1.12,
                        colors: isRecording
                            ? [
                                const Color(0xFFFFECDD).withValues(alpha: 0.13),
                                const Color(0xFFC0646E).withValues(alpha: 0.48),
                                const Color(0xFF4D222B).withValues(alpha: 0.66),
                              ]
                            : [
                                const Color(0xFFFFECDD).withValues(alpha: 0.07),
                                bgColor,
                                const Color(0xFF120B0E).withValues(alpha: 0.54),
                              ],
                        stops: const [0, 0.56, 1],
                      ),
                      border: Border.all(
                        color: isRecording
                            ? const Color(0xFFFFC6B5).withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.035),
                      ),
                      boxShadow: isRecording
                          ? [
                              BoxShadow(
                                color: const Color(0xFFC0646E)
                                    .withValues(alpha: 0.24),
                                blurRadius: 14,
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
            ),
          ),
        );
      },
    );
  }
}
