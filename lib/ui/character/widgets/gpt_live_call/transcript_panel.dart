import 'package:flutter/material.dart';

import 'package:memex/data/services/gpt_live/gpt_live_protocol.dart';

class GptLiveTranscriptPanel extends StatelessWidget {
  const GptLiveTranscriptPanel({super.key, required this.turns});

  final List<GptLiveTurn> turns;

  @override
  Widget build(BuildContext context) {
    if (turns.isEmpty) {
      return const Center(
        child: Text(
          '说点什么吧',
          style: TextStyle(color: Colors.white30, fontSize: 17),
        ),
      );
    }
    return ListView.separated(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: turns.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final turn = turns[turns.length - 1 - index];
        return Text(
          turn.text.toString().trim(),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: turn.fromUser ? Colors.white54 : Colors.white,
            fontSize: turn.fromUser ? 16 : 21,
            height: 1.35,
            fontWeight: turn.fromUser ? FontWeight.w400 : FontWeight.w500,
          ),
        );
      },
    );
  }
}
