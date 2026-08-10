import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logging/logging.dart';
import 'package:crypto/crypto.dart';
import 'package:share_handler/share_handler.dart';

import 'package:memex/data/services/backup_import_intent_service.dart';
import 'package:memex/data/services/backup_service.dart';
import 'package:memex/ui/main_screen/widgets/input_sheet.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';

/// Handles system share intents (text, images) and forwards them
/// as drafts into the input sheet for user confirmation.
class ShareIntentHandler {
  static const _clipboardLinkMarker = '__here_i_am_share_copied_link__';

  final Logger logger;
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;
  final void Function(InputData) onSharedDraft;
  final Future<void> Function(String backupFilePath) onBackupFileShared;

  StreamSubscription<SharedMedia>? _mediaSubscription;
  StreamSubscription<String>? _backupPathSubscription;
  bool _isHandlingShare = false;
  bool _isHandlingBackupFile = false;

  ShareIntentHandler({
    required this.logger,
    required this.scaffoldMessengerKey,
    required this.onSharedDraft,
    required this.onBackupFileShared,
  });

  void init() {
    final handler = ShareHandlerPlatform.instance;

    // Handle initial shared media when app is launched from share
    handler.getInitialSharedMedia().then((media) async {
      if (media != null) {
        await _handleSharedMedia(media);
        await handler.resetInitialSharedMedia();
      }
    }).catchError((error, stack) {
      logger.warning('Error reading initial shared media: $error');
    });

    // Listen for media shared while app is in memory
    _mediaSubscription = handler.sharedMediaStream.listen((media) {
      _handleSharedMedia(media);
    }, onError: (err) {
      logger.warning('Error in sharedMediaStream: $err');
    });

    final backupIntentService = BackupImportIntentService.instance;
    backupIntentService.consumeInitialBackupPath().then((path) {
      if (path != null) {
        _handleBackupFile(path);
      }
    }).catchError((err, stack) {
      logger.warning('Error reading initial backup import intent: $err');
    });
    _backupPathSubscription = backupIntentService.backupPathStream.listen(
      (path) {
        _handleBackupFile(path);
      },
      onError: (err) {
        logger.warning('Error in backupPathStream: $err');
      },
    );
  }

  Future<void> _handleSharedMedia(SharedMedia media) async {
    if (_isHandlingShare) return;

    _isHandlingShare = true;

    try {
      final attachments = media.attachments ?? const [];
      final backupFilePath = _firstBackupFilePath(attachments);
      if (backupFilePath != null) {
        await _handleBackupFile(backupFilePath);
        return;
      }

      // Ensure model is configured before accepting shared content
      final configs = await UserStorage.getLLMConfigs();
      final hasValidConfig = configs.any((c) => c.isValid);
      if (!hasValidConfig) {
        ToastHelper.showErrorWithKey(
          scaffoldMessengerKey,
          UserStorage.l10n.modelNotConfiguredSubmitHint,
        );
        return;
      }

      var trimmedText = media.content == null || media.content!.trim().isEmpty
          ? null
          : media.content!.trim();

      if (trimmedText == _clipboardLinkMarker) {
        trimmedText = await _readCopiedLink();
        if (trimmedText == null) {
          ToastHelper.showErrorWithKey(
            scaffoldMessengerKey,
            '剪贴板里没有可分享的链接',
          );
          return;
        }
      }

      // Reading Companion links are no longer auto-captured here. Both
      // system share intents and chat-pasted links now flow through the
      // same path: the link becomes a chat message, the companion reads
      // the article body via TransientFetchCache, and saving to a memory
      // card only happens when the user explicitly records it (double-tap
      // / "存一下" / floating ball). This unifies the semantics of "share"
      // with image attachments: read first, save only on explicit action.
      final imageFiles = <XFile>[];

      for (final attachment in attachments) {
        if (attachment == null) continue;
        final path = attachment.path;
        if (path.isEmpty) continue;

        final isImageAttachment =
            attachment.type == SharedAttachmentType.image ||
                _looksLikeImageFile(path);
        if (isImageAttachment) {
          imageFiles.add(XFile(path));
        }
      }

      // Generate hashes similar to InputSheet
      String? textHash;
      List<String>? imageHashes;

      if (trimmedText != null && trimmedText.isNotEmpty) {
        textHash = md5.convert(utf8.encode(trimmedText)).toString();
      }

      if (imageFiles.isNotEmpty) {
        imageHashes = [];
        for (final xFile in imageFiles) {
          try {
            final file = File(xFile.path);
            final length = await file.length();
            final rawHashStr =
                'photo_${file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : file.path}_$length';
            logger.info('Generating hash for shared image: $rawHashStr');
            imageHashes.add(md5.convert(utf8.encode(rawHashStr)).toString());
          } catch (e) {
            imageHashes.add(md5
                .convert(utf8.encode(
                    'photo_${xFile.path}_${DateTime.now().millisecondsSinceEpoch}'))
                .toString());
          }
        }
      }

      final inputData = InputData(
        text: trimmedText,
        images: imageFiles,
        textHash: textHash,
        imageHashes: imageHashes,
      );

      if (inputData.isEmpty) return;

      onSharedDraft(inputData);
    } catch (e, stackTrace) {
      logger.severe('Error handling shared media: $e', e, stackTrace);
      ToastHelper.showErrorWithKey(scaffoldMessengerKey, e);
    } finally {
      _isHandlingShare = false;
    }
  }

  Future<String?> _readCopiedLink() async {
    // Android 10+ can deny clipboard reads while an app is in the background.
    // This retry happens after MainActivity has been brought to the foreground
    // by the explicit long-press share action.
    await Future<void>.delayed(const Duration(milliseconds: 180));
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      final value = clipboard?.text?.trim();
      if (value == null || value.isEmpty) return null;
      return RegExp(r'https?://\S+', caseSensitive: false).hasMatch(value)
          ? value
          : null;
    } on PlatformException catch (error) {
      logger.warning('Clipboard link read failed: $error');
      return null;
    }
  }

  void dispose() {
    _mediaSubscription?.cancel();
    _backupPathSubscription?.cancel();
  }

  Future<void> _handleBackupFile(String rawPath) async {
    if (_isHandlingBackupFile) return;
    final backupFilePath = _normalizeFilePath(rawPath);
    if (!BackupService.isMemexBackupFile(backupFilePath)) {
      ToastHelper.showErrorWithKey(
        scaffoldMessengerKey,
        UserStorage.l10n.invalidBackupFile,
      );
      return;
    }

    _isHandlingBackupFile = true;
    try {
      await onBackupFileShared(backupFilePath);
    } catch (e, stackTrace) {
      logger.severe('Error handling backup file: $e', e, stackTrace);
      ToastHelper.showErrorWithKey(scaffoldMessengerKey, e);
    } finally {
      _isHandlingBackupFile = false;
    }
  }

  String? _firstBackupFilePath(List<SharedAttachment?> attachments) {
    for (final attachment in attachments) {
      if (attachment == null) continue;
      final path = attachment.path;
      if (path.isEmpty) continue;
      final normalizedPath = _normalizeFilePath(path);
      if (attachment.type == SharedAttachmentType.file &&
          BackupService.isMemexBackupFile(normalizedPath)) {
        return normalizedPath;
      }
    }
    return null;
  }

  String _normalizeFilePath(String filePath) {
    if (filePath.startsWith('file://')) {
      try {
        return Uri.parse(filePath).toFilePath();
      } catch (_) {
        return filePath.replaceFirst('file://', '');
      }
    }
    return filePath;
  }

  bool _looksLikeImageFile(String path) {
    final lowerPath = path.toLowerCase();
    const imageExtensions = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.heic',
      '.heif',
      '.bmp',
      '.tif',
      '.tiff',
    ];
    return imageExtensions.any(lowerPath.endsWith);
  }
}
