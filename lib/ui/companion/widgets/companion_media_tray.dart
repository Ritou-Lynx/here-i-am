import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:memex/data/services/photo_suggestion_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

const _trayPanel = Color(0xF0101218);
const _trayPanelSoft = Color(0xFF1B1D24);
const _trayText = Color(0xFFF2ECE0);
const _trayMuted = Color(0xFF9E9A94);
const _trayAccent = Color(0xFFE4D6BD);

/// Lightweight media picker for companion chat.
///
/// Opens from the + button in the chat input bar. Selected images are
/// immediately forwarded to the parent via [onImagesPicked]. The parent
/// owns selection state and renders previews inline in the input bar.
/// This tray has no send button — it is a pure picker.
class CompanionMediaTray extends StatefulWidget {
  const CompanionMediaTray({
    super.key,
    required this.isOpen,
    required this.onImagesPicked,
    this.loadSuggestions,
  });

  final bool isOpen;
  final void Function(List<XFile> images) onImagesPicked;
  final Future<List<List<EnhancedPhoto>>> Function()? loadSuggestions;

  @override
  State<CompanionMediaTray> createState() => _CompanionMediaTrayState();
}

class _CompanionMediaTrayState extends State<CompanionMediaTray> {
  final _logger = getLogger('CompanionMediaTray');
  final _imagePicker = ImagePicker();
  List<List<EnhancedPhoto>>? _suggestedClusters;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.isOpen) _loadSuggestions();
  }

  @override
  void didUpdateWidget(covariant CompanionMediaTray oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen && !oldWidget.isOpen) _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final clusters = await (widget.loadSuggestions ??
          PhotoSuggestionService.fetchAndClusterRecentPhotos)();
      if (!mounted) return;
      setState(() {
        _suggestedClusters = clusters;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      _logger.warning('Failed to load photo suggestions', e, stackTrace);
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickCameraPhoto() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (image != null) {
        widget.onImagesPicked([image]);
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _pickAlbumPhotos() async {
    try {
      final assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: AssetPickerConfig(
          maxAssets: 9,
          requestType: RequestType.image,
          filterOptions: FilterOptionGroup(
            containsPathModified: true,
            createTimeCond: DateTimeCond.def().copyWith(ignore: true),
            updateTimeCond: DateTimeCond.def().copyWith(ignore: true),
            videoOption: const FilterOption(
              durationConstraint: DurationConstraint(
                min: Duration.zero,
                max: Duration.zero,
              ),
            ),
          ),
        ),
      );
      if (assets == null || assets.isEmpty) return;
      final images = <XFile>[];
      for (final asset in assets) {
        final image = await PhotoSuggestionService.assetToXFile(asset);
        if (image != null) images.add(image);
      }
      if (images.isNotEmpty) {
        widget.onImagesPicked(images);
      }
    } catch (e) {
      _showError(e);
    }
  }

  void _pickCluster(List<EnhancedPhoto> cluster) {
    widget.onImagesPicked(cluster.map((p) => p.xFile).toList());
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: widget.isOpen
          ? Container(
              margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              decoration: BoxDecoration(
                color: _trayPanel,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.11),
                ),
              ),
              child: SizedBox(
                height: 70,
                child: Row(
                  children: [
                    Expanded(child: _buildSuggestions()),
                    const SizedBox(width: 8),
                    _ActionButton(
                      icon: Icons.photo_library_outlined,
                      label: UserStorage.l10n.photos,
                      onTap: _pickAlbumPhotos,
                    ),
                    const SizedBox(width: 8),
                    _ActionButton(
                      icon: Icons.camera_alt_outlined,
                      label: UserStorage.l10n.camera,
                      onTap: _pickCameraPhoto,
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildSuggestions() {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final clusters = _suggestedClusters ?? const <List<EnhancedPhoto>>[];
    if (clusters.isEmpty) {
      return Center(
        child: Text(
          UserStorage.l10n.smartSuggesting,
          style: const TextStyle(color: _trayMuted, fontSize: 12),
        ),
      );
    }
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: clusters.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, index) => _SuggestionCluster(
        cluster: clusters[index],
        onTap: () => _pickCluster(clusters[index]),
      ),
    );
  }
}

class _SuggestionCluster extends StatelessWidget {
  const _SuggestionCluster({
    required this.cluster,
    required this.onTap,
  });

  final List<EnhancedPhoto> cluster;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: _trayPanelSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...cluster.take(3).map(
                  (photo) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AssetEntityImage(
                        photo.entity,
                        width: 54,
                        height: 54,
                        fit: BoxFit.cover,
                        isOriginal: false,
                        thumbnailSize: const ThumbnailSize.square(120),
                        thumbnailFormat: ThumbnailFormat.jpeg,
                      ),
                    ),
                  ),
                ),
            if (cluster.length > 3)
              Text(
                '+${cluster.length - 3}',
                style: const TextStyle(color: _trayText, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 62,
        decoration: BoxDecoration(
          color: _trayPanelSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _trayAccent, size: 20),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _trayText, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
