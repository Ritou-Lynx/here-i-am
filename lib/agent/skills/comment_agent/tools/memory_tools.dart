// ignore_for_file: non_constant_identifier_names

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/domain/models/character_memory.dart';
import 'package:memex/data/services/file_operation_utils.dart';
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as path;
import 'dart:async'; // Import Completer and Future

class MemoryBlockDefinition {
  final String description;
  final Map<String, String> metadata;
  final String? storagePath;
  const MemoryBlockDefinition(
      {this.description = '', this.metadata = const {}, this.storagePath});
}

class MemoryToolFactory {
  final String userId;
  final String? defaultCharacterId;
  final Map<String, MemoryBlockDefinition> blockDefinitions;

  MemoryToolFactory({
    required this.userId,
    this.defaultCharacterId,
    this.blockDefinitions = const {},
  });

  /// Track ongoing operations per key (file path or character ID)
  static final Map<String, Future<void>> _locks = {};

  /// Execute operation with lock to prevent concurrent writes
  Future<T> _withLock<T>(String key, Future<T> Function() operation) async {
    // Wait for existing lock
    while (_locks.containsKey(key)) {
      await _locks[key]!;
    }

    // Create new lock
    final completer = Completer<void>();
    _locks[key] = completer.future;

    try {
      return await operation();
    } finally {
      completer.complete();
      _locks.remove(key);
    }
  }

  /// Execute operation with file lock (normalizes path)
  Future<T> _withFileLock<T>(
      String filePath, Future<T> Function() operation) async {
    final normalizedPath = path.normalize(path.absolute(filePath));
    return _withLock(normalizedPath, operation);
  }

  /// Execute operation with character lock
  Future<T> _withCharacterLock<T>(
      String characterId, Future<T> Function() operation) async {
    final key = 'char:$characterId';
    return _withLock(key, operation);
  }

  /// Build the MemoryReadTool
  Tool buildMemoryReadTool() {
    return Tool(
      name: 'MemoryRead',
      description:
          '''Reads memory blocks from the current character's memory storage. You can use this tool to directly access specific memory blocks using labels.
Assume this tool can read all memory blocks.

Usage:
- The `labels` parameter is optional; if provided, only memory blocks with matching labels are returned.
- If `labels` is omitted or empty, all memory blocks are returned.
- Results are returned in a structured format with line numbers starting from 1 for the block's value.
- This format allows you to precisely reference content for editing.
- You have the ability to call multiple tools in a single response.
''',
      parameters: {
        'type': 'object',
        'properties': {
          'labels': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Optional list of memory block labels to filter by (e.g. ["user", "persona"]).'
          }
        },
        'required': []
      },
      executable: (List<dynamic>? labels) async {
        final targetId = defaultCharacterId;
        if (targetId == null) {
          return "Error: No default character set.";
        }

        final character =
            await CharacterService.instance.getCharacter(userId, targetId);
        if (character == null) {
          return "Error: Character $targetId not found.";
        }

        // Start with character memory
        List<CharacterMemoryBlock> allBlocks = List.from(character.memory);

        // Merge/Override with file-based blocks
        for (var entry in blockDefinitions.entries) {
          final label = entry.key;
          final def = entry.value;
          if (def.storagePath != null) {
            // If defined in file, remove any existing entry from char memory (to avoid duplicates/stale data)
            allBlocks.removeWhere((b) => b.label == label);

            // Read from file
            try {
              final block = await _readBlockFromFile(def.storagePath!, label);
              if (block != null) {
                allBlocks.add(block);
              } else {
                // File doesn't exist or empty, use default empty block if needed,
                // or just reliance on definition description.
                // We create a placeholder so it shows up
                allBlocks.add(CharacterMemoryBlock(
                    label: label, value: '', description: def.description));
              }
            } catch (e) {
              // Log error or ignore? Safer to just proceed or show error in value?
              allBlocks.add(CharacterMemoryBlock(
                  label: label,
                  value: '<Error reading file: $e>',
                  description: def.description));
            }
          }
        }

        List<CharacterMemoryBlock> blocksToReturn = allBlocks;
        if (labels != null && labels.isNotEmpty) {
          final labelSet = labels.map((e) => e.toString()).toSet();
          blocksToReturn = blocksToReturn
              .where((block) => labelSet.contains(block.label))
              .toList();
        }

        return _formatMemoryBlocks(blocksToReturn);
      },
    );
  }

  /// Build the MemoryEditTool
  Tool buildMemoryEditTool() {
    return Tool(
      name: 'MemoryEdit',
      description: '''Performs precise string replacement in memory blocks.

Usage:
- When editing memory, ensure you preserve the exact indentation (tabs/spaces).
- If `old_string` is not unique in the block, the edit will fail. Either provide a larger string with more surrounding context to make it unique, or use `replace_all` to change every instance of `old_string`.
- Use `replace_all` to replace and rename strings throughout the block. This parameter is useful for cases like renaming nouns.
- If the target memory block (label) doesn't exist, it will be automatically created (requires empty old_string).
''',
      parameters: {
        'type': 'object',
        'properties': {
          'label': {
            'type': 'string',
            'description': 'The label of the memory block to edit (e.g. "user")'
          },
          'old_string': {
            'type': 'string',
            'description':
                'The exact text to find and replace in the memory value. Ensure you include enough context/unique text to match.'
          },
          'new_string': {
            'type': 'string',
            'description': 'The new text to replace old_string with.'
          },
          'replace_all': {
            'type': 'boolean',
            'description':
                'Whether to replace all occurrences of old_string. Defaults to false.'
          }
        },
        'required': ['label', 'old_string', 'new_string']
      },
      executable: (
        String label,
        String old_string,
        String new_string, [
        bool? replace_all,
      ]) async {
        final shouldReplaceAll = replace_all ?? false;

        // Check if this label is file-based
        final def = blockDefinitions[label];
        if (def?.storagePath != null) {
          return _editFileMemory(def!.storagePath!, label, old_string,
              new_string, shouldReplaceAll);
        }

        final targetId = defaultCharacterId;
        if (targetId == null) {
          return "Error: No default character set.";
        }

        return _withCharacterLock(targetId, () async {
          try {
            final character =
                await CharacterService.instance.getCharacter(userId, targetId);
            if (character == null) {
              return "Error: Character $targetId not found.";
            }

            final List<CharacterMemoryBlock> newMemory =
                List.from(character.memory);

            final existingIndex =
                newMemory.indexWhere((block) => block.label == label);

            if (existingIndex == -1) {
              if (old_string.isEmpty) {
                newMemory.add(CharacterMemoryBlock(
                  label: label,
                  value: new_string,
                  description: '', // Description managed by defaults
                ));
                await _saveMemory(targetId, newMemory);
                return "New memory block '$label' created.";
              } else {
                return "Error: Memory block '$label' not found. Cannot search for old_string.";
              }
            }

            final currentBlock = newMemory[existingIndex];
            final currentValue = currentBlock.value;

            if (old_string.isEmpty) {
              return "Error: old_string is empty. To create a new block, use a new label. To edit, provide text to match.";
            }

            if (!currentValue.contains(old_string)) {
              return "Error: old_string not found in memory block '$label'.";
            }

            final matches = old_string.allMatches(currentValue).length;
            if (matches > 1 && !shouldReplaceAll) {
              return "Error: old_string matches $matches times. Please provide more context to match a unique string or set replace_all to true.";
            }

            final newValue = shouldReplaceAll
                ? currentValue.replaceAll(old_string, new_string)
                : currentValue.replaceFirst(old_string, new_string);

            newMemory[existingIndex] = currentBlock.copyWith(value: newValue);
            await _saveMemory(targetId, newMemory);

            return "Memory block '$label' updated successfully.";
          } catch (e) {
            return "Error updating memory: $e";
          }
        });
      },
    );
  }

  Future<String> _editFileMemory(String path, String label, String oldString,
      String newString, bool replaceAll) async {
    return _withFileLock(path, () async {
      try {
        CharacterMemoryBlock? block = await _readBlockFromFile(path, label);

        if (block == null) {
          if (oldString.isEmpty) {
            // Create new
            block = CharacterMemoryBlock(
                label: label, value: newString, description: '');
            await _writeBlockToFile(path, block);
            return "New memory block '$label' created in file.";
          } else {
            return "Error: Memory block '$label' not found in file. Cannot search for old_string.";
          }
        }

        final currentValue = block.value;
        if (oldString.isEmpty) {
          return "Error: old_string is empty. To edit, provide text to match.";
        }

        if (!currentValue.contains(oldString)) {
          return "Error: old_string not found in memory block '$label'.";
        }

        final matches = oldString.allMatches(currentValue).length;
        if (matches > 1 && !replaceAll) {
          return "Error: oldString matches $matches times. Please provide more context to match a unique string or set replace_all to true.";
        }

        final newValue = replaceAll
            ? currentValue.replaceAll(oldString, newString)
            : currentValue.replaceFirst(oldString, newString);

        final newBlock = block.copyWith(value: newValue);
        await _writeBlockToFile(path, newBlock);

        return "Memory block '$label' updated successfully in file.";
      } catch (e) {
        return "Error updating file memory: $e";
      }
    });
  }

  /// Build the MemoryWriteTool
  Tool buildMemoryWriteTool() {
    return Tool(
      name: 'MemoryWrite',
      description: '''Writes memory blocks to the character's memory storage.

Usage:
- If a memory block exists with the provided label, this tool will overwrite the existing block.
- Always prioritize editing existing blocks in the workspace.
- If the target memory block doesn't exist, it will be automatically created.
''',
      parameters: {
        'type': 'object',
        'properties': {
          'label': {
            'type': 'string',
            'description': 'The label of the memory block to write to.'
          },
          'value': {
            'type': 'string',
            'description': 'The content to write to the memory block.'
          }
        },
        'required': ['label', 'value']
      },
      executable: (String label, String value) async {
        // Check if this label is file-based
        final def = blockDefinitions[label];
        if (def?.storagePath != null) {
          return _writeFileMemory(def!.storagePath!, label, value);
        }

        final targetId = defaultCharacterId;
        if (targetId == null) {
          return "Error: No default character set.";
        }

        return _withCharacterLock(targetId, () async {
          try {
            final character =
                await CharacterService.instance.getCharacter(userId, targetId);
            if (character == null) {
              return "Error: Character $targetId not found.";
            }

            final List<CharacterMemoryBlock> newMemory =
                List.from(character.memory);

            final existingIndex =
                newMemory.indexWhere((block) => block.label == label);

            if (existingIndex != -1) {
              // Overwrite existing
              newMemory[existingIndex] = newMemory[existingIndex].copyWith(
                value: value,
              );
            } else {
              // Create new
              newMemory.add(CharacterMemoryBlock(
                label: label,
                value: value,
                description: '', // Description managed by defaults
              ));
            }

            await _saveMemory(targetId, newMemory);

            return "Memory block '$label' written successfully.";
          } catch (e) {
            return "Error writing memory: $e";
          }
        });
      },
    );
  }

  Future<String> _writeFileMemory(
      String path, String label, String value) async {
    return _withFileLock(path, () async {
      try {
        // Do not set description from definition, so it remains empty and won't be saved to file (using default fallback on read)
        final block =
            CharacterMemoryBlock(label: label, value: value, description: '');
        await _writeBlockToFile(path, block);
        return "Memory block '$label' written successfully to file.";
      } catch (e) {
        return "Error writing file memory: $e";
      }
    });
  }

  Future<void> _saveMemory(
      String charId, List<CharacterMemoryBlock> memory) async {
    await CharacterService.instance.updateCharacter(
      userId: userId,
      characterId: charId,
      updates: {'memory': memory.map((e) => e.toJson()).toList()},
    );
  }

  String _formatMemoryBlocks(List<CharacterMemoryBlock> blocks) {
    if (blocks.isEmpty && blockDefinitions.isEmpty) {
      return "";
    }

    final buffer = StringBuffer();
    // Create a map for easy lookup
    final blockMap = {for (var b in blocks) b.label: b};

    // Combine all labels: existing blocks + definitions
    final allLabels = {...blockMap.keys, ...blockDefinitions.keys}.toList();

    for (final label in allLabels) {
      final block = blockMap[label];
      final definition = blockDefinitions[label];

      String value = '';
      String description = '';
      Map<String, String> metadata = {};

      if (block != null) {
        value = block.value;
        description = block.description;
      }

      // Resolve description and metadata from definitions
      if (definition != null) {
        if (description.isEmpty) {
          description = definition.description;
        }
        metadata.addAll(definition.metadata);
      }

      // Dynamic metadata
      metadata['chars_current'] = value.length.toString();

      buffer.writeln('<$label>');
      buffer.writeln('<description>');
      if (description.isNotEmpty) {
        buffer.writeln(description);
      }
      buffer.writeln('</description>');

      if (metadata.isNotEmpty) {
        buffer.writeln('<metadata>');
        for (final entry in metadata.entries) {
          buffer.writeln('- ${entry.key}=${entry.value}');
        }
        buffer.writeln('</metadata>');
      }

      buffer.writeln('<value>');
      if (value.isNotEmpty) {
        buffer.writeln(value);
      }
      buffer.writeln('</value>');
      buffer.writeln('</$label>');
      buffer.writeln();
    }

    return buffer.toString();
  }

  Future<CharacterMemoryBlock?> _readBlockFromFile(
      String path, String label) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;

    try {
      final yaml = loadYaml(content);
      if (yaml is Map) {
        // Should match the label we expect? Or we just read whatever is in the file?
        // User said "store to a common place". If the file contains ONE block, we just read it.
        // Warning: simple casting
        final map = Map<String, dynamic>.from(yaml);
        // If file doesn't have label, check if we should enforce it?
        // Assuming file content matches CharacterMemoryBlock structure
        return CharacterMemoryBlock.fromJson(map);
      }
    } catch (e) {
      // invalid yaml
    }
    return null;
  }

  Future<void> _writeBlockToFile(
      String path, CharacterMemoryBlock block) async {
    final file = File(path);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    final yamlContent = _blockToYaml(block);
    await file.writeAsString(yamlContent);
  }

  String _blockToYaml(CharacterMemoryBlock block) {
    // Simple YAML dumper
    final buffer = StringBuffer();
    // Escape quotes if needed
    String escape(String s) => s.replaceAll('"', r'\"');

    buffer.writeln('label: "${escape(block.label)}"');

    // Only write description if it is NOT empty and NOT the default definition description
    final defaultDesc = blockDefinitions[block.label]?.description;
    if (block.description.isNotEmpty && block.description != defaultDesc) {
      buffer.writeln('description: "${escape(block.description)}"');
    }

    if (block.value.contains('\n')) {
      buffer.writeln('value: |');
      for (final line in block.value.split('\n')) {
        // Indent lines
        buffer.writeln('  $line');
      }
    } else {
      buffer.writeln('value: "${escape(block.value)}"');
    }
    return buffer.toString();
  }
}
