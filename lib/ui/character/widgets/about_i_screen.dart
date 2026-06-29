import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/media_service.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/core/widgets/avatar_picker.dart';
import 'package:memex/ui/core/widgets/character_avatar.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';

/// "关于 I" — minimal settings page for the singleton I.
class AboutIScreen extends StatefulWidget {
  const AboutIScreen({super.key});

  @override
  State<AboutIScreen> createState() => _AboutIScreenState();
}

class _AboutIScreenState extends State<AboutIScreen> {
  final _logger = getLogger('AboutIScreen');

  bool _isLoading = true;
  CharacterModel? _character;
  String? _avatarPreview;
  String? _chatBackgroundPreview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final primary =
          await CharacterService.instance.getPrimaryCompanion(userId);
      if (!mounted) return;
      setState(() {
        _character = primary;
        _avatarPreview = primary?.avatar;
        _chatBackgroundPreview = primary?.chatBackground;
        _isLoading = false;
      });
    } catch (e, s) {
      _logger.severe('Failed to load I', e, s);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAvatar() async {
    final picked = await showAvatarPicker(
      context,
      _avatarPreview ?? '',
      onPickGallery: _pickAvatarFromGallery,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (!CharacterService.isRelativeAvatarPath(picked)) {
        _avatarPreview = picked;
      }
    });
    await _persistField('avatar', picked);
  }

  Future<String?> _pickAvatarFromGallery() async {
    try {
      final pickedPath = await pickAvatarImageFromGallery();
      if (pickedPath == null) return null;
      final userId = await UserStorage.getUserId();
      if (userId == null) return null;
      final imported = await MediaService.instance.importImage(
        userId: userId,
        sourcePath: pickedPath,
      );
      if (!mounted) return null;
      setState(() => _avatarPreview = imported.absolutePath);
      return imported.relativePath;
    } catch (e, s) {
      _logger.warning('Failed to pick avatar', e, s);
      if (mounted) {
        ToastHelper.showError(
          context,
          UserStorage.l10n.operationFailed(e.toString()),
        );
      }
      return null;
    }
  }

  Future<void> _pickChatBackground() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );
      if (picked == null) return;
      final userId = await UserStorage.getUserId();
      if (userId == null) return;
      final imported = await MediaService.instance.importImage(
        userId: userId,
        sourcePath: picked.path,
      );
      if (!mounted) return;
      setState(() => _chatBackgroundPreview = imported.absolutePath);
      await _persistField('chat_background', imported.relativePath);
    } catch (e, s) {
      _logger.warning('Failed to pick chat background', e, s);
      if (mounted) {
        ToastHelper.showError(
          context,
          UserStorage.l10n.operationFailed(e.toString()),
        );
      }
    }
  }

  Future<void> _clearChatBackground() async {
    setState(() => _chatBackgroundPreview = null);
    await _persistField('chat_background', null);
  }

  Future<void> _persistField(String key, dynamic value) async {
    final character = _character;
    if (character == null) return;
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) return;
      final updated = await CharacterService.instance.updateCharacter(
        userId: userId,
        characterId: character.id,
        updates: {key: value},
      );
      if (!mounted || updated == null) return;
      setState(() {
        _character = updated;
        _avatarPreview = updated.avatar;
        _chatBackgroundPreview = updated.chatBackground;
      });
    } catch (e, s) {
      _logger.warning('Failed to persist $key', e, s);
      if (mounted) {
        ToastHelper.showError(
          context,
          UserStorage.l10n.saveFailed(e.toString()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于 I')),
      body: _isLoading
          ? const Center(child: AgentLogoLoading())
          : _character == null
              ? const Center(child: Text('未初始化'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: _buildAvatar()),
                      const SizedBox(height: 32),
                      _sectionLabel('聊天背景'),
                      const SizedBox(height: 8),
                      _buildChatBackgroundPicker(),
                      const SizedBox(height: 32),
                      _sectionLabel('Dreaming'),
                      const SizedBox(height: 8),
                      _buildDreamingPlaceholder(),
                    ],
                  ),
                ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF64748B),
      ),
    );
  }

  Widget _buildAvatar() {
    return GestureDetector(
      onTap: _pickAvatar,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          CharacterAvatar(
            avatar: _avatarPreview,
            name: _character?.name ?? 'I',
            size: 120,
          ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Colors.black87,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.camera_alt_outlined,
              size: 16,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBackgroundPicker() {
    final preview = _chatBackgroundPreview;
    final hasBackground =
        preview != null && preview.isNotEmpty && File(preview).existsSync();

    return GestureDetector(
      onTap: _pickChatBackground,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          image: hasBackground
              ? DecorationImage(
                  image: FileImage(File(preview)),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: hasBackground
            ? Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: GestureDetector(
                    onTap: _clearChatBackground,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              )
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 32,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '选择聊天背景图',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildDreamingPlaceholder() {
    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Center(
        child: Text(
          'Dreaming · 即将到来',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }
}
