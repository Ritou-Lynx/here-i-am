import 'package:flutter/material.dart';
import 'package:memex/ui/core/cards/ui/glass_card.dart';

class QuoteCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onTap;

  const QuoteCard({super.key, required this.data, this.onTap});

  @override
  Widget build(BuildContext context) {
    final String content = data['content'] ?? '';
    final String? author = data['author'];
    final String? source = data['source'];

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(24),
      backgroundColor:
          const Color(0xFF1E1E2E), // Dark theme for quotes as per example
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.format_quote, color: Colors.white24, size: 32),
          const SizedBox(height: 16),
          Text(
            content,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontFamily: 'Serif', // Use system Serif or custom if available
              fontStyle: FontStyle.italic,
              height: 1.4,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          if (author != null || source != null)
            Column(
              children: [
                Container(
                  width: 40,
                  height: 1,
                  color: Colors.white24,
                ),
                const SizedBox(height: 12),
                if (author != null)
                  Text(
                    author,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                      letterSpacing: 0.5,
                    ),
                  ),
                if (source != null)
                  Text(
                    source,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white38,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
