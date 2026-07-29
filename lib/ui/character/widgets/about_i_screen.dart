import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/media_service.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/ui/core/themes/here_iam_theme_tokens.dart';
import 'package:memex/ui/core/themes/spring_rain_chat_color_controller.dart';
import 'package:memex/ui/core/themes/spring_rain_chat_tokens.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/core/widgets/avatar_picker.dart';
import 'package:memex/ui/core/widgets/character_avatar.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';

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

  final _ttsVoiceIdController = TextEditingController();
  final _ttsVoiceIdFocusNode = FocusNode();
  Timer? _ttsVoiceIdSaveDebounce;
  String? _lastPersistedTtsVoiceId;

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
        _ttsVoiceIdController.text = primary?.ttsVoiceId ?? '';
        _lastPersistedTtsVoiceId = primary?.ttsVoiceId;
        _isLoading = false;
      });
    } catch (e, s) {
      _logger.severe('Failed to load I', e, s);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _ttsVoiceIdSaveDebounce?.cancel();
    if (_isTtsVoiceIdDirty()) {
      _flushTtsVoiceIdSave();
    }
    _ttsVoiceIdController.dispose();
    _ttsVoiceIdFocusNode.dispose();
    super.dispose();
  }

  bool _isTtsVoiceIdDirty() {
    final current = _ttsVoiceIdController.text.trim();
    final saved = _lastPersistedTtsVoiceId ?? '';
    return current != saved;
  }

  void _onTtsVoiceIdChanged(String _) {
    _ttsVoiceIdSaveDebounce?.cancel();
    _ttsVoiceIdSaveDebounce = Timer(
      const Duration(milliseconds: 600),
      _saveTtsVoiceId,
    );
  }

  void _flushTtsVoiceIdSave() {
    _ttsVoiceIdSaveDebounce?.cancel();
    if (_isTtsVoiceIdDirty()) {
      _saveTtsVoiceId();
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

  Future<void> _saveTtsVoiceId() async {
    final value = _ttsVoiceIdController.text.trim();
    final next = value.isEmpty ? null : value;
    if ((_lastPersistedTtsVoiceId ?? '') == (next ?? '')) return;
    final character = _character;
    if (character == null) return;
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) return;
      final updated = await CharacterService.instance.updateCharacter(
        userId: userId,
        characterId: character.id,
        updates: {'tts_voice_id': next},
      );
      if (!mounted) return;
      if (updated != null) {
        setState(() {
          _character = updated;
          _lastPersistedTtsVoiceId = next;
        });
      }
    } catch (e, s) {
      _logger.warning('Failed to persist tts_voice_id', e, s);
      if (mounted) {
        ToastHelper.showError(
          context,
          UserStorage.l10n.saveFailed(e.toString()),
        );
      }
    }
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

  String _fileImageKey(String path) {
    try {
      final stat = File(path).statSync();
      return '$path:${stat.size}:${stat.modified.millisecondsSinceEpoch}';
    } catch (_) {
      return path;
    }
  }

  @override
  Widget build(BuildContext context) {
    const skin = HereIamThemeTokens.springRainDaydream;
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: skin.background,
        elevation: 0,
        centerTitle: true,
        title: Text(
          '关于 I',
          style: TextStyle(
            color: skin.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: IconThemeData(color: skin.textSecondary),
      ),
      body: _isLoading
          ? const Center(child: AgentLogoLoading())
          : _character == null
              ? Center(
                  child: Text(
                    '未初始化',
                    style: TextStyle(color: skin.textMuted),
                  ),
                )
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
                      _sectionLabel('用户文字颜色'),
                      const SizedBox(height: 8),
                      _buildUserColorPicker(),
                      const SizedBox(height: 32),
                      _sectionLabel('TTS 语音'),
                      const SizedBox(height: 4),
                      Text(
                        '将所选 TTS 服务的 Voice ID 粘贴到此处（在 Settings → TTS 语音 中设置服务商）',
                        style: TextStyle(fontSize: 12, color: skin.textMuted),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _ttsVoiceIdController,
                        focusNode: _ttsVoiceIdFocusNode,
                        style: TextStyle(fontSize: 16, color: skin.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Voice ID',
                          hintStyle: TextStyle(
                            color: skin.textMuted,
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: skin.glassFill,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: skin.glassStroke),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: skin.glassStroke),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: skin.accent),
                          ),
                        ),
                        onChanged: _onTtsVoiceIdChanged,
                        onSubmitted: (_) => _flushTtsVoiceIdSave(),
                        onTapOutside: (_) => _flushTtsVoiceIdSave(),
                      ),
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
    const skin = HereIamThemeTokens.springRainDaydream;
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: skin.textMuted,
      ),
    );
  }

  Widget _buildAvatar() {
    const skin = HereIamThemeTokens.springRainDaydream;
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
            decoration: BoxDecoration(
              color: skin.surfaceDeep,
              shape: BoxShape.circle,
              border: Border.all(color: skin.glassStroke),
            ),
            child: Icon(
              Icons.camera_alt_outlined,
              size: 16,
              color: skin.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBackgroundPicker() {
    const skin = HereIamThemeTokens.springRainDaydream;
    final preview = _chatBackgroundPreview;
    final hasBackground =
        preview != null && preview.isNotEmpty && File(preview).existsSync();

    return GestureDetector(
      onTap: _pickChatBackground,
      child: Container(
        key: ValueKey(hasBackground ? _fileImageKey(preview) : 'empty-bg'),
        height: 140,
        decoration: BoxDecoration(
          color: skin.glassFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: skin.glassStroke),
          image: hasBackground
              ? DecorationImage(
                  image: FileImage(
                    File(preview),
                    scale: 1,
                  ),
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
                      color: skin.textMuted,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '选择聊天背景图',
                      style: TextStyle(
                        fontSize: 13,
                        color: skin.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildDreamingPlaceholder() {
    const skin = HereIamThemeTokens.springRainDaydream;
    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: skin.glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: skin.glassStroke),
      ),
      child: Center(
        child: Text(
          'Dreaming · 即将到来',
          style: TextStyle(
            fontSize: 13,
            color: skin.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildUserColorPicker() {
    final controller = context.watch<SpringRainChatColorController>();
    const chat = SpringRainChatTokens.springRainDaydream;
    const options = SpringRainChatColorController.options;
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _buildUserColorSwatch(
              option: options[i],
              chat: chat,
              isSelected: controller.selectedId == options[i].id,
              onTap: () => controller.select(options[i].id),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUserColorSwatch({
    required SpringRainUserColorOption option,
    required SpringRainChatTokens chat,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    const skin = HereIamThemeTokens.springRainDaydream;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: chat.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? skin.highlight : skin.glassStroke,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '用户消息',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                fontFamily: chat.fontFamily,
                color: option.color,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  Icon(
                    Icons.check_circle,
                    size: 14,
                    color: skin.highlight,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? skin.textPrimary : skin.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
