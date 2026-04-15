import 'dart:io';
import 'dart:convert';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/api_exception.dart';
import 'package:path/path.dart' as p;

final _logger = getLogger('PkmEndpoint');
final _fileSystemService = FileSystemService.instance;

/// List PKM directory contents
///
/// Args:
///   path: path relative to PKM root (e.g. "Projects/MyProject"), empty = root
///
/// Returns:
///   Map with items and current_path
///     - items: list of { name, path, is_directory, size }
///     - current_path: current path string
Future<Map<String, dynamic>> listPkmDirectory({String? path}) async {
  _logger.info('listPkmDirectory called: path=$path');

  try {
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      throw ApiException('User not logged in, cannot access PKM directory');
    }

    // Get PKM root
    final pkmRoot = _fileSystemService.getPkmPath(userId);
    final pkmRootDir = Directory(pkmRoot);

    // If PKM dir does not exist, return empty list
    if (!await pkmRootDir.exists()) {
      _logger.info('PKM directory does not exist: $pkmRoot');
      return {
        'items': <Map<String, dynamic>>[],
        'current_path': '',
      };
    }

    // Build target path
    Directory targetDir;
    final dirPath = path;
    if (dirPath != null && dirPath.isNotEmpty) {
      // Prevent path traversal
      final targetPath = p.normalize(p.join(pkmRoot, dirPath));
      final resolvedTarget = p.absolute(targetPath);
      final resolvedRoot = p.absolute(pkmRoot);

      if (!resolvedTarget.startsWith(resolvedRoot)) {
        throw ApiException('Invalid path: path is not safe');
      }

      targetDir = Directory(targetPath);

      // Special handling for English/Chinese root PKM categories
      if (!await targetDir.exists()) {
        final Map<String, String> categoryMapping = {
          'Projects': '项目',
          'Areas': '领域',
          'Resources': '资源',
          'Archives': '归档',
        };

        if (categoryMapping.containsKey(dirPath)) {
          final chinesePath = p.join(pkmRoot, categoryMapping[dirPath]!);
          final chineseDir = Directory(chinesePath);
          if (await chineseDir.exists()) {
            targetDir = chineseDir;
          }
        }
      }
    } else {
      targetDir = pkmRootDir;
    }

    if (!await targetDir.exists()) {
      _logger.info('PKM directory not found: $dirPath, returning empty list');
      return {
        'items': <Map<String, dynamic>>[],
        'current_path': dirPath ?? '',
      };
    }

    // List directory contents
    final items = <Map<String, dynamic>>[];
    try {
      await for (final entity in targetDir.list()) {
        // Skip hidden files
        final entityPath = entity.path;
        final name = p.basename(entityPath);
        if (name.startsWith('.')) {
          continue;
        }

        final isDirectory = await FileSystemEntity.isDirectory(entityPath);
        final item = <String, dynamic>{
          'name': name,
          'path': p.relative(entityPath, from: pkmRoot),
          'is_directory': isDirectory,
        };

        if (!isDirectory) {
          final file = File(entityPath);
          if (await file.exists()) {
            final stat = await file.stat();
            item['size'] = stat.size;
          }
        }

        items.add(item);
      }
    } catch (e) {
      _logger.severe('Error listing directory ${targetDir.path}: $e');
      throw ApiException('Failed to list directory: $e');
    }

    // Compute relative path
    final currentPath = targetDir.path != pkmRoot
        ? p.relative(targetDir.path, from: pkmRoot)
        : '';

    return {
      'items': items,
      'current_path': currentPath,
    };
  } catch (e) {
    _logger.severe('Failed to list PKM directory: $e');
    rethrow;
  }
}

/// Read PKM file content
///
/// Args:
///   filePath: path relative to PKM root (e.g. "Projects/MyProject/readme.md")
///
/// Returns:
///   Map with path, content, is_binary
///     - path: file path
///     - content: text or base64 for binary
///     - is_binary: bool
Future<Map<String, dynamic>> readPkmFileEndpoint(String filePath) async {
  _logger.info('readPkmFile called: filePath=$filePath');

  try {
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      throw ApiException('User not logged in, cannot read PKM file');
    }

    if (filePath.isEmpty) {
      throw ApiException('File path from root cannot be empty');
    }

    // Get PKM root
    final pkmRoot = _fileSystemService.getPkmPath(userId);

    // Build target file path
    final normalizedPath = p.normalize(p.join(pkmRoot, filePath));
    final resolvedTarget = p.absolute(normalizedPath);
    final resolvedRoot = p.absolute(pkmRoot);

    // Prevent path traversal
    if (!resolvedTarget.startsWith(resolvedRoot)) {
      throw ApiException('Invalid path: path is not safe');
    }

    final targetFile = File(resolvedTarget);

    if (!await targetFile.exists()) {
      throw ApiException('File not found: $filePath');
    }

    // Check file size (max 10MB)
    final stat = await targetFile.stat();
    if (stat.size > 10 * 1024 * 1024) {
      throw ApiException('File too large (max 10MB)');
    }

    // Read file content
    try {
      // Try read as text
      String content;
      bool isBinary = false;

      try {
        content = await targetFile.readAsString(
            encoding: const Utf8Codec(allowMalformed: true));
        // Check for invalid UTF-8
        if (content.contains('\uFFFD')) {
          // Replacement char present, likely binary
          throw FormatException('Binary file detected');
        }
        isBinary = false;
      } catch (e) {
        // If binary, return base64
        final bytes = await targetFile.readAsBytes();
        content = base64Encode(bytes);
        isBinary = true;
      }

      final relativePath = p.relative(targetFile.path, from: pkmRoot);

      return {
        'path': relativePath,
        'content': content,
        'is_binary': isBinary,
      };
    } catch (e) {
      _logger.severe('Error reading file ${targetFile.path}: $e');
      throw ApiException('Failed to read file: $e');
    }
  } catch (e) {
    _logger.severe('Failed to read PKM file $filePath: $e');
    rethrow;
  }
}
