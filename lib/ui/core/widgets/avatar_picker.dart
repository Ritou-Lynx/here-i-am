import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/core/widgets/character_avatar.dart';
import 'package:memex/utils/user_storage.dart';

Future<String?> pickAvatarImageFromGallery() async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 512,
    maxHeight: 512,
    imageQuality: 85,
  );
  return picked?.path;
}

/// Shows a bottom sheet for selecting a local image from the gallery.
/// Returns the selected image path, or null if dismissed.
Future<String?> showAvatarPicker(
  BuildContext context,
  String currentAvatar, {
  Future<String?> Function()? onPickGallery,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _AvatarPickerSheet(
      currentSeed: currentAvatar,
      onPickGallery: onPickGallery,
    ),
  );
}

class _AvatarPickerSheet extends StatefulWidget {
  const _AvatarPickerSheet({
    required this.currentSeed,
    this.onPickGallery,
  });
  final String currentSeed;
  final Future<String?> Function()? onPickGallery;

  @override
  State<_AvatarPickerSheet> createState() => _AvatarPickerSheetState();
}

class _AvatarPickerSheetState extends State<_AvatarPickerSheet> {
  Future<void> _pickImageFromGallery() async {
    final onPickGallery = widget.onPickGallery;
    if (onPickGallery == null) return;

    try {
      final avatar = await onPickGallery();
      if (avatar != null && mounted) Navigator.pop(context, avatar);
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              UserStorage.l10n.chooseAvatar,
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            // Current avatar
            if (widget.currentSeed.isNotEmpty) ...[
              CharacterAvatar(
                avatar: widget.currentSeed,
                name: widget.currentSeed,
                size: 64,
              ),
              const SizedBox(height: 4),
              Text(
                UserStorage.l10n.localeName == 'zh' ? '当前头像' : 'Current',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (widget.onPickGallery != null) ...[
              ListTile(
                leading:
                    const Icon(Icons.photo_library, color: AppColors.primary),
                title: Text(UserStorage.l10n.selectFromAlbum),
                onTap: _pickImageFromGallery,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
