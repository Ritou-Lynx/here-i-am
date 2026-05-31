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
/// Text and voice stay in the chat composer. This tray only adds recent photo
/// suggestions, album selection, and camera capture.
class CompanionMediaTray extends StatefulWidget {
  const CompanionMediaTray({
    super.key,
    required this.isOpen,
    required this.onSubmit,
    this.loadSuggestions,
  });

  final bool isOpen;
  final Future<bool> Function(List<XFile> images) onSubmit;
  final Future<List<List<EnhancedPhoto>>> Function()? loadSuggestions;

  @override
  State<CompanionMediaTray> createState() => _CompanionMediaTrayState();
}

class _CompanionMediaTrayState extends State<CompanionMediaTray> {
  final _logger = getLogger('CompanionMediaTray');
  final _imagePicker = ImagePicker();
  final _selectedImages = <XFile>[];
  final _assetByPath = <String, AssetEntity>{};
  List<List<EnhancedPhoto>>? _suggestedClusters;
  bool _isLoading = false;
  bool _isSubmitting = false;

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
      if (image != null) _addImage(image);
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
      if (assets == null) return;
      for (final asset in assets) {
        final image = await PhotoSuggestionService.assetToXFile(asset);
        if (image == null) continue;
        _assetByPath[image.path] = asset;
        _addImage(image);
      }
    } catch (e) {
      _showError(e);
    }
  }

  void _toggleCluster(List<EnhancedPhoto> cluster) {
    final allSelected = cluster.every(
      (photo) => _selectedImages.any((image) => image.path == photo.xFile.path),
    );
    setState(() {
      for (final photo in cluster) {
        if (allSelected) {
          _selectedImages.removeWhere(
            (image) => image.path == photo.xFile.path,
          );
          _assetByPath.remove(photo.xFile.path);
        } else if (!_selectedImages.any(
          (image) => image.path == photo.xFile.path,
        )) {
          _selectedImages.add(photo.xFile);
          _assetByPath[photo.xFile.path] = photo.entity;
        }
      }
    });
  }

  void _addImage(XFile image) {
    if (_selectedImages.any((current) => current.path == image.path)) return;
    setState(() => _selectedImages.add(image));
  }

  void _removeImage(XFile image) {
    setState(() {
      _selectedImages.removeWhere((current) => current.path == image.path);
      _assetByPath.remove(image.path);
    });
  }

  Future<void> _submit() async {
    if (_selectedImages.isEmpty || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    final success = await widget.onSubmit(List<XFile>.from(_selectedImages));
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      if (success) {
        _selectedImages.clear();
        _assetByPath.clear();
      }
    });
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_selectedImages.isNotEmpty) ...[
                    _buildSelectedRow(),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
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
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildSelectedRow() {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedImages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                final image = _selectedImages[index];
                return GestureDetector(
                  onTap: () => _removeImage(image),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: _buildSelectedImage(image),
                      ),
                      const Positioned(
                        right: 2,
                        top: 2,
                        child: Icon(
                          Icons.remove_circle,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _submit,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _trayAccent.withValues(alpha: 0.9),
              ),
              child: _isSubmitting
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF5B5346),
                      ),
                    )
                  : const Icon(
                      Icons.arrow_upward_rounded,
                      color: Color(0xFF5B5346),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedImage(XFile image) {
    final asset = _assetByPath[image.path];
    if (asset != null) {
      return AssetEntityImage(
        asset,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        isOriginal: false,
        thumbnailSize: const ThumbnailSize.square(120),
        thumbnailFormat: ThumbnailFormat.jpeg,
      );
    }
    return Image.file(
      File(image.path),
      width: 48,
      height: 48,
      fit: BoxFit.cover,
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
        selected: clusters[index].every(
          (photo) =>
              _selectedImages.any((image) => image.path == photo.xFile.path),
        ),
        onTap: () => _toggleCluster(clusters[index]),
      ),
    );
  }
}

class _SuggestionCluster extends StatelessWidget {
  const _SuggestionCluster({
    required this.cluster,
    required this.selected,
    required this.onTap,
  });

  final List<EnhancedPhoto> cluster;
  final bool selected;
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
            color: selected
                ? _trayAccent.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.1),
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
            if (selected)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 17,
                  color: _trayAccent,
                ),
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
