import 'dart:io';

import 'package:flutter/material.dart';
import 'package:memex/ui/core/widgets/local_image.dart';

/// Returns true if the avatar string represents a local image file path
/// rather than a legacy non-image value.
bool isImageAvatar(String? avatar) {
  if (avatar == null || avatar.isEmpty) return false;
  final lower = avatar.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp') ||
      lower.contains('/');
}

/// A unified character avatar widget for custom images and local placeholders.
///
/// If [avatar] looks like a file path (contains '/' or ends with image extension),
/// it renders using [LocalImage] in a circle. Otherwise it shows the initial
/// from [name].
class CharacterAvatar extends StatelessWidget {
  const CharacterAvatar({
    super.key,
    required this.avatar,
    required this.name,
    this.size = 48,
    this.backgroundColor,
  });

  /// The avatar value from CharacterModel. Legacy non-image values are ignored.
  final String? avatar;

  /// Character name, used for the placeholder initial.
  final String name;

  /// Avatar diameter.
  final double size;

  /// Background color for placeholder avatars.
  final Color? backgroundColor;

  String get _imageKey {
    final value = avatar ?? '';
    if (!value.startsWith('/')) return value;
    try {
      final stat = File(value).statSync();
      return '$value:${stat.size}:${stat.modified.millisecondsSinceEpoch}';
    } catch (_) {
      return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isImageAvatar(avatar)) {
      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: LocalImage(
            key: ValueKey(_imageKey),
            url: avatar!,
            fit: BoxFit.cover,
            width: size,
            height: size,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) return child;
              return _placeholder();
            },
            errorBuilder: (_, __, ___) => _placeholder(),
          ),
        ),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    return AvatarInitialPlaceholder(
      name: name,
      size: size,
      backgroundColor: backgroundColor,
    );
  }
}

/// A warm local avatar placeholder showing the first grapheme of [name].
class AvatarInitialPlaceholder extends StatelessWidget {
  const AvatarInitialPlaceholder({
    super.key,
    required this.name,
    required this.size,
    this.backgroundColor,
  });

  final String name;
  final double size;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final trimmedName = name.trim();
    final initial = trimmedName.isEmpty
        ? null
        : trimmedName.characters.first.toUpperCase();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor ?? const Color(0xFFE9D8C8),
      ),
      child: initial == null
          ? Icon(
              Icons.person,
              size: size * 0.52,
              color: const Color(0xFF6B4F3A),
            )
          : Text(
              initial,
              style: TextStyle(
                color: const Color(0xFF6B4F3A),
                fontSize: size * 0.42,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
    );
  }
}
