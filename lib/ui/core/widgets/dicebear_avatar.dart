import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Builds a DiceBear Notionists avatar URL from a seed string.
String dicebearUrl(String seed) {
  final encoded = Uri.encodeComponent(seed);
  return 'https://api.dicebear.com/7.x/notionists/svg?seed=$encoded';
}

/// Displays a DiceBear Notionists avatar as a circle.
///
/// [seed] is used to generate the avatar. If null, shows a placeholder icon.
/// The widget loads the SVG from the network and caches it via flutter_svg.
class DiceBearAvatar extends StatelessWidget {
  const DiceBearAvatar({
    super.key,
    required this.seed,
    this.size = 48,
    this.backgroundColor,
  });

  final String? seed;
  final double size;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    if (seed == null || seed!.isEmpty) {
      return _placeholder();
    }

    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: backgroundColor ?? const Color(0xFFEEF2FF),
        child: SvgPicture.network(
          dicebearUrl(seed!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholderBuilder: (_) => _loadingIndicator(),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? const Color(0xFFEEF2FF),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person,
        size: size * 0.5,
        color: const Color(0xFF5B6CFF),
      ),
    );
  }

  Widget _loadingIndicator() {
    return Container(
      width: size,
      height: size,
      color: backgroundColor ?? const Color(0xFFEEF2FF),
      child: Center(
        child: SizedBox(
          width: size * 0.3,
          height: size * 0.3,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF5B6CFF),
          ),
        ),
      ),
    );
  }
}
