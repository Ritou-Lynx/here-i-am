/// Tests for the object store behind real image / attachment import:
/// files are copied into `objects/…`, refs stay relative and stable across
/// "restart" (new store instance), path traversal is blocked, and the
/// document JSON never carries source paths or binaries.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/rich_text_asset_ref.dart';
import 'package:memex/domain/whiteboard/rich_text_object_store.dart';

void main() {
  late Directory baseDir;
  late Directory sourceDir;
  late RichTextObjectStore store;

  setUp(() {
    baseDir = Directory.systemTemp.createTempSync('object_store_test_');
    sourceDir = Directory.systemTemp.createTempSync('object_source_test_');
    store = RichTextObjectStore(baseDir);
  });

  tearDown(() {
    if (baseDir.existsSync()) baseDir.deleteSync(recursive: true);
    if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
  });

  File writeSource(String name, [String content = 'hello']) {
    final f = File('${sourceDir.path}${Platform.pathSeparator}$name');
    f.writeAsStringSync(content);
    return f;
  }

  group('import', () {
    test('copies the file into objects/ and returns a stable relative ref',
        () async {
      writeSource('截图.png');
      final ref = await store.importFile(
        '${sourceDir.path}${Platform.pathSeparator}截图.png',
        alt: '截图.png',
      );
      expect(ref.objectRef, startsWith('objects/'));
      expect(ref.objectRef, endsWith('.png'));
      expect(ref.mimeType, equals('image/png'));
      expect(ref.alt, equals('截图.png'));

      // The source path never leaks into the ref.
      expect(ref.objectRef.contains(sourceDir.path), isFalse);
      expect(ref.objectRef.contains('\\'), isFalse);

      // The object file physically exists.
      final resolved = store.resolveFile(ref);
      expect(resolved, isNotNull);
      expect(resolved!.readAsStringSync(), equals('hello'));
    });

    test('survives "restart": a new store instance resolves the same ref',
        () async {
      writeSource('note.txt');
      final ref = await store.importFile(
        '${sourceDir.path}${Platform.pathSeparator}note.txt',
      );
      // Simulate a restart: fresh store over the same base dir.
      final restarted = RichTextObjectStore(baseDir);
      final file = restarted.resolveFile(ref);
      expect(file, isNotNull);
      expect(file!.readAsStringSync(), equals('hello'));
    });

    test('identical bytes reuse one content-addressed object', () async {
      final first = await store.importBytes(
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
      );
      final second = await store.importBytes(
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
      );

      expect(first.objectRef, second.objectRef);
      expect(first.refId, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(store.objectsDirectory.listSync().whereType<File>(), hasLength(1));
    });

    test('infers mime type by extension', () async {
      writeSource('doc.pdf');
      final ref = await store
          .importFile('${sourceDir.path}${Platform.pathSeparator}doc.pdf');
      expect(ref.mimeType, equals('application/pdf'));
    });

    test('unknown extensions default to octet-stream', () async {
      writeSource('blob.xyz');
      final ref = await store
          .importFile('${sourceDir.path}${Platform.pathSeparator}blob.xyz');
      expect(ref.mimeType, equals('application/octet-stream'));
    });

    test('import of a missing file throws', () async {
      expect(
        () =>
            store.importFile('${sourceDir.path}${Platform.pathSeparator}nope'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('resolve safety', () {
    test('absolute object refs are rejected', () {
      final ref = RichTextAssetRef(
        refId: 'r',
        objectRef: Platform.pathSeparator == '\\'
            ? 'C:\\evil\\file.png'
            : '/etc/passwd',
        mimeType: 'image/png',
      );
      expect(store.resolveFile(ref), isNull);
    });

    test('path traversal object refs are rejected', () {
      const ref = RichTextAssetRef(
        refId: 'r',
        objectRef: '../outside.png',
        mimeType: 'image/png',
      );
      expect(store.resolveFile(ref), isNull);
    });

    test('refs outside objects/ are rejected', () {
      const ref = RichTextAssetRef(
        refId: 'r',
        objectRef: 'other/dir.png',
        mimeType: 'image/png',
      );
      expect(store.resolveFile(ref), isNull);
    });

    test('non-existent object files resolve to null', () {
      const ref = RichTextAssetRef(
        refId: 'r',
        objectRef: 'objects/ghost.png',
        mimeType: 'image/png',
      );
      expect(store.resolveFile(ref), isNull);
    });

    test('symlink object cannot read or delete an external target', () async {
      final external = writeSource('outside.png', 'must survive');
      await store.objectsDirectory.create(recursive: true);
      final link = Link(
        '${store.objectsDirectory.path}${Platform.pathSeparator}linked.png',
      );
      try {
        await link.create(external.path);
      } on FileSystemException {
        // Windows can forbid symlink creation without Developer Mode. The
        // production guard rejects every non-regular leaf via typeSync.
        return;
      }
      const ref = RichTextAssetRef(
        refId: 'linked',
        objectRef: 'objects/linked.png',
        mimeType: 'image/png',
      );

      expect(store.resolveFile(ref), isNull);
      await store.deleteRef(ref);
      expect(external.readAsStringSync(), 'must survive');
      expect(link.existsSync(), isTrue);
    });
  });

  group('delete', () {
    test('deleteRef removes the object file', () async {
      writeSource('gone.png');
      final ref = await store
          .importFile('${sourceDir.path}${Platform.pathSeparator}gone.png');
      expect(store.resolveFile(ref), isNotNull);
      await store.deleteRef(ref);
      expect(store.resolveFile(ref), isNull);
    });

    test('deleteRef is a no-op for unsafe refs', () async {
      const ref = RichTextAssetRef(
        refId: 'r',
        objectRef: '../evil.png',
        mimeType: 'image/png',
      );
      await store.deleteRef(ref); // must not throw
    });

    test('deleteRef conservatively retains shared digest objects', () async {
      final first = await store.importBytes(
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
      );
      final second = await store.importBytes(
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
      );
      expect(first.objectRef, second.objectRef);

      await store.deleteRef(first);

      expect(store.resolveFile(second), isNotNull);
    });
  });

  group('document JSON safety', () {
    test('saved document JSON carries only the stable object ref', () async {
      writeSource('photo.jpg');
      final ref = await store.importFile(
        '${sourceDir.path}${Platform.pathSeparator}photo.jpg',
        alt: 'photo.jpg',
      );
      final json = jsonEncode({
        'schema_version': 2,
        'asset_refs': [ref.toJson()],
      });
      expect(json.contains(sourceDir.path), isFalse);
      expect(json.contains('file://'), isFalse);
      expect(json.contains('base64'), isFalse);
      expect(json.contains('objects/'), isTrue);
    });
  });
}
