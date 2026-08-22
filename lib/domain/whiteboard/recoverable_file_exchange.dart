/// Crash-recoverable single-file replacement using `.tmp` and `.bak` peers.
///
/// This is not a filesystem transaction: Dart cannot fsync the containing
/// directory on every supported platform. It does, however, keep a valid old
/// or new copy throughout the exchange and deterministically repairs an
/// interrupted exchange on the next startup/read.
library;

import 'dart:convert';
import 'dart:io';

typedef FileContentsValidator = bool Function(String contents);

class RecoverableFileExchange {
  RecoverableFileExchange._();

  static File tempFor(File target) => File('${target.path}.tmp');
  static File backupFor(File target) => File('${target.path}.bak');

  static Future<void> write(
    File target,
    String contents, {
    required FileContentsValidator validator,
  }) async {
    await target.parent.create(recursive: true);
    await recover(target, validator: validator);

    final temp = tempFor(target);
    final backup = backupFor(target);
    if (await temp.exists()) await temp.delete();
    await temp.writeAsString(contents, flush: true);
    if (!await _isValid(temp, validator)) {
      throw const FormatException('temporary replacement is invalid');
    }

    // A valid temp now protects the operation. Preserve the current target
    // as backup instead of deleting it before installing the replacement.
    if (await target.exists()) {
      if (await backup.exists()) await backup.delete();
      await target.rename(backup.path);
    }
    await _installTemp(target, validator: validator);
  }

  static void writeSync(
    File target,
    String contents, {
    required FileContentsValidator validator,
  }) {
    target.parent.createSync(recursive: true);
    recoverSync(target, validator: validator);

    final temp = tempFor(target);
    final backup = backupFor(target);
    if (temp.existsSync()) temp.deleteSync();
    temp.writeAsStringSync(contents, flush: true);
    if (!_isValidSync(temp, validator)) {
      throw const FormatException('temporary replacement is invalid');
    }

    if (target.existsSync()) {
      if (backup.existsSync()) backup.deleteSync();
      target.renameSync(backup.path);
    }
    _installTempSync(target, validator: validator);
  }

  /// Repairs leftovers and returns whether a valid target is available.
  ///
  /// Preference order encodes the exchange phases: valid target (completed),
  /// valid temp (new write prepared), then valid backup (old write preserved).
  /// When [maxBytes] is set, candidates larger than the bound are rejected
  /// without loading their contents.
  static Future<bool> recover(
    File target, {
    required FileContentsValidator validator,
    int? maxBytes,
  }) async {
    assert(maxBytes == null || maxBytes >= 0);
    final temp = tempFor(target);
    final backup = backupFor(target);
    if (await _isValid(target, validator, maxBytes: maxBytes)) {
      await _deleteIfExists(temp);
      await _deleteIfExists(backup);
      return true;
    }
    if (await _isValid(temp, validator, maxBytes: maxBytes)) {
      await _installTemp(
        target,
        validator: validator,
        maxBytes: maxBytes,
      );
      return true;
    }
    if (await _isValid(backup, validator, maxBytes: maxBytes)) {
      if (await target.exists()) await target.delete();
      await backup.rename(target.path);
      await _deleteIfExists(temp);
      return true;
    }
    return false;
  }

  static bool recoverSync(
    File target, {
    required FileContentsValidator validator,
  }) {
    final temp = tempFor(target);
    final backup = backupFor(target);
    if (_isValidSync(target, validator)) {
      _deleteIfExistsSync(temp);
      _deleteIfExistsSync(backup);
      return true;
    }
    if (_isValidSync(temp, validator)) {
      _installTempSync(target, validator: validator);
      return true;
    }
    if (_isValidSync(backup, validator)) {
      if (target.existsSync()) target.deleteSync();
      backup.renameSync(target.path);
      _deleteIfExistsSync(temp);
      return true;
    }
    return false;
  }

  static Future<void> _installTemp(
    File target, {
    required FileContentsValidator validator,
    int? maxBytes,
  }) async {
    final temp = tempFor(target);
    final backup = backupFor(target);
    if (await target.exists()) {
      if (await backup.exists()) {
        // Both temp and backup protect this removal.
        await target.delete();
      } else {
        await target.rename(backup.path);
      }
    }
    try {
      await temp.rename(target.path);
      if (!await _isValid(target, validator, maxBytes: maxBytes)) {
        throw const FormatException('installed replacement is invalid');
      }
      await _deleteIfExists(backup);
    } catch (_) {
      if (await backup.exists()) {
        final targetIsValid = await _isValid(
          target,
          validator,
          maxBytes: maxBytes,
        );
        if (!targetIsValid) {
          if (await target.exists()) await target.delete();
          await backup.rename(target.path);
        }
      }
      rethrow;
    }
  }

  static void _installTempSync(
    File target, {
    required FileContentsValidator validator,
  }) {
    final temp = tempFor(target);
    final backup = backupFor(target);
    if (target.existsSync()) {
      if (backup.existsSync()) {
        target.deleteSync();
      } else {
        target.renameSync(backup.path);
      }
    }
    try {
      temp.renameSync(target.path);
      if (!_isValidSync(target, validator)) {
        throw const FormatException('installed replacement is invalid');
      }
      _deleteIfExistsSync(backup);
    } catch (_) {
      if (backup.existsSync() && !_isValidSync(target, validator)) {
        if (target.existsSync()) target.deleteSync();
        backup.renameSync(target.path);
      }
      rethrow;
    }
  }

  static Future<bool> _isValid(
    File file,
    FileContentsValidator validator, {
    int? maxBytes,
  }) async {
    if (!await file.exists()) return false;
    try {
      if (maxBytes != null) {
        final beforeLength = await file.length();
        if (beforeLength > maxBytes) return false;
        final reader = await file.open();
        try {
          final bytes = await reader.read(maxBytes + 1);
          if (bytes.length > maxBytes || await file.length() != bytes.length) {
            return false;
          }
          return validator(utf8.decode(bytes, allowMalformed: false));
        } finally {
          await reader.close();
        }
      }
      return validator(await file.readAsString());
    } catch (_) {
      return false;
    }
  }

  static bool _isValidSync(File file, FileContentsValidator validator) {
    if (!file.existsSync()) return false;
    try {
      return validator(file.readAsStringSync());
    } catch (_) {
      return false;
    }
  }

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }

  static void _deleteIfExistsSync(File file) {
    if (file.existsSync()) file.deleteSync();
  }
}
