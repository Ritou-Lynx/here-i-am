import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/core/widgets/dicebear_avatar.dart';
import 'package:memex/utils/user_storage.dart';

/// Default seed words used to generate random DiceBear avatars.
const _seedPool = [
  'Felix',
  'Luna',
  'Milo',
  'Aria',
  'Leo',
  'Nova',
  'Kai',
  'Zoe',
  'Finn',
  'Iris',
  'Sage',
  'Ember',
  'Atlas',
  'Cleo',
  'Orion',
  'Jade',
  'River',
  'Skye',
  'Wren',
  'Aspen',
  'Cedar',
  'Maple',
  'Storm',
  'Blaze',
  'Coral',
  'Dusk',
  'Echo',
  'Frost',
  'Glow',
  'Haze',
  'Ivy',
  'Jazz',
  'Kite',
  'Lark',
  'Moss',
  'Neon',
  'Opal',
  'Peak',
  'Quill',
  'Reed',
  'Star',
  'Tide',
  'Vale',
  'Wave',
  'Zen',
  'Bolt',
  'Dune',
  'Fern',
  'Hawk',
  'Lynx',
];

/// Picks [count] random seeds from the pool, optionally excluding [current].
List<String> _randomSeeds(int count, {String? current}) {
  final rng = Random();
  final pool = List<String>.from(_seedPool);
  if (current != null) pool.remove(current);
  pool.shuffle(rng);
  return pool.take(count).toList();
}

/// Shows a bottom sheet with 5 DiceBear avatar options and a refresh button.
/// Returns the selected seed string, or null if dismissed.
Future<String?> showAvatarPicker(BuildContext context, String currentAvatar) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _AvatarPickerSheet(currentSeed: currentAvatar),
  );
}

class _AvatarPickerSheet extends StatefulWidget {
  const _AvatarPickerSheet({required this.currentSeed});
  final String currentSeed;

  @override
  State<_AvatarPickerSheet> createState() => _AvatarPickerSheetState();
}

class _AvatarPickerSheetState extends State<_AvatarPickerSheet> {
  late List<String> _seeds;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _seeds = _randomSeeds(5, current: widget.currentSeed);
  }

  void _refresh() {
    setState(() {
      _seeds = _randomSeeds(5, current: widget.currentSeed);
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
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
            DiceBearAvatar(seed: widget.currentSeed, size: 64),
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

          // Avatar row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _seeds.map((seed) {
              final isSelected = _selected == seed;
              return GestureDetector(
                onTap: () {
                  setState(() => _selected = seed);
                  Navigator.pop(context, seed);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: AppColors.primary, width: 2.5)
                        : Border.all(color: Colors.transparent, width: 2.5),
                  ),
                  child: DiceBearAvatar(
                    seed: seed,
                    size: 56,
                    backgroundColor: Colors.grey[50],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Refresh button — directly below avatars so the association is clear
          GestureDetector(
            onTap: _refresh,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, size: 16, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    UserStorage.l10n.localeName == 'zh' ? '换一批' : 'Shuffle',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
