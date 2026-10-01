import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/android_activity_normalizer.dart';

// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/android_activity_signal_platform.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/activity_outbox_process_lease.dart';

final class _BoundaryFileSystem implements AndroidPrivateOutboxFileSystem {
  final types = <String, FileSystemEntityType>{};
  final resolved = <String, String>{};
  final reads = <String>[];

  @override
  FileSystemEntityType typeWithoutFollowingLinks(String path) {
    reads.add('type:$path');
    return types[path] ?? FileSystemEntityType.notFound;
  }

  @override
  String resolveDirectory(String path) {
    reads.add('resolve:$path');
    final result = resolved[path];
    if (result == null) throw const FileSystemException('fixture read refused');
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const status = <String, Object>{
    'version': 1,
    'session_id': 'session-a',
    'observation_id': 'observation-a',
    'revision': 4,
    'state': 'running',
    'enabled': true,
    'reason': 'ready',
  };

  test(
    'observation status accepts only the frozen exact running shape',
    () async {
      const channel = MethodChannel('a3f_r3_observation_status_valid');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getObservationStatus');
        return status;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final result = await MethodChannelAndroidActivitySignalPlatform(
        channel: channel,
      ).getObservationStatus();

      expect(result.state, AndroidNativeObservationState.running);
      expect(result.enabled, isTrue);
      expect(result.revision, 4);
    },
  );

  test(
    'observation status fails closed for unknown reason or enabled terminal',
    () async {
      const channel = MethodChannel('a3f_r3_observation_status_invalid');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var response = Map<String, Object>.from(status)..['reason'] = 'private';
      messenger.setMockMethodCallHandler(channel, (call) async => response);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final platform = MethodChannelAndroidActivitySignalPlatform(
        channel: channel,
      );

      await expectLater(
        platform.getObservationStatus(),
        throwsA(isA<AndroidActivityException>()),
      );

      response = Map<String, Object>.from(status)
        ..['state'] = 'stopped'
        ..['enabled'] = true
        ..['reason'] = 'user_stop';
      await expectLater(
        platform.getObservationStatus(),
        throwsA(isA<AndroidActivityException>()),
      );
    },
  );
  test(
    'native seven-key activation shape succeeds and three-key truncation fails',
    () async {
      const channel = MethodChannel('r3_native_activation_contract');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final platform = MethodChannelAndroidActivitySignalPlatform(
        channel: channel,
      );
      Map<String, Object?> response = {
        'enabled': true,
        'readiness': 'ready',
        'usage_source': 'android_usage_events',
        'screen_source': 'android_screen_state',
        'usage_permission': 'granted',
        'counters': {'query_failures': 0, 'dropped_events': 0},
        'observation_status': status,
      };
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'acquireDiagnosticOutboxLease') {
          final source = (call.arguments as Map)['source'];
          return {'source': source, 'lease_token': 'token-$source'};
        }
        if (call.method == 'releaseDiagnosticOutboxLease') {
          return {'released': true};
        }
        return response;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final leases = <AndroidActivitySource, ActivityOutboxProcessLease>{};
      final claimants = <AndroidActivitySource, Object>{};
      for (final source in AndroidActivitySource.values) {
        final lease = await platform.acquireDiagnosticOutboxLease(source);
        final claimant = Object();
        claimants[source] = claimant;
        lease.claimFileAccess(claimant, source.wireValue);
        leases[source] = lease;
      }
      Future<AndroidNativeActivation> activate() =>
          platform.activateObservation(
            enabled: true,
            integrityAuthorityReady: true,
            boundSources: AndroidActivitySource.values.toSet(),
            categoryMapping: const {},
            leases: leases,
          );
      expect((await activate()).enabled, isTrue);
      final valid = Map<String, Object?>.from(response);
      response = {
        'enabled': true,
        'readiness': 'ready',
        'observation_status': status,
      };
      await expectLater(activate(), throwsA(isA<AndroidActivityException>()));
      response = {
        ...valid,
        'enabled': false,
        'readiness': 'activity_authority_invalid',
        'observation_status': null,
      };
      expect((await activate()).observationStatus, isNull);
      for (final mutation in [
        {'usage_source': 'wrong'},
        {'screen_source': 'wrong'},
        {'usage_permission': 'private'},
        {
          'counters': {'private': 1},
        },
        {
          'counters': {'query_failures': -1},
        },
        {
          'counters': {'query_failures': 'one'},
        },
      ]) {
        response = {...valid, ...mutation};
        await expectLater(activate(), throwsA(isA<AndroidActivityException>()));
      }
      response = valid;
      final first = leases[AndroidActivitySource.usageEvents]!;
      await expectLater(
        platform.releaseDiagnosticOutboxLease(first),
        throwsA(isA<AndroidActivityException>()),
      );
      for (final source in AndroidActivitySource.values) {
        leases[source]!.releaseFileAccess(claimants[source]!);
        await platform.releaseDiagnosticOutboxLease(leases[source]!);
      }
      await expectLater(activate(), throwsA(isA<AndroidActivityException>()));
    },
  );

  test(
    'strict status rejects non-integer version and revision, empty identity and extra keys',
    () async {
      const channel = MethodChannel('r3_strict_shapes');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Map<String, Object?> response = status;
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final platform = MethodChannelAndroidActivitySignalPlatform(
        channel: channel,
      );
      for (final mutation in [
        {'version': 1.0},
        {'revision': 1.0},
        {'revision': -1},
        {'session_id': ''},
        {'observation_id': ''},
        {'extra': 'private'},
      ]) {
        response = {...status, ...mutation};
        await expectLater(
          platform.getObservationStatus(),
          throwsA(isA<AndroidActivityException>()),
        );
      }
    },
  );
  test(
    'R3 pathfix Dart trusted ancestor alias returns canonical no_backup child',
    () async {
      const channel = MethodChannel('r3_pathfix_ancestor_alias');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const rawApp = '/data/user/0/com.memexlab.hereiam.v3';
      const canonicalApp = '/data/data/com.memexlab.hereiam.v3';
      final fs = _BoundaryFileSystem()
        ..types[rawApp] = FileSystemEntityType.directory
        ..types['$rawApp/no_backup'] = FileSystemEntityType.directory
        ..types[canonicalApp] = FileSystemEntityType.directory
        ..types['$canonicalApp/no_backup'] = FileSystemEntityType.directory
        ..resolved[rawApp] = canonicalApp
        ..resolved['$rawApp/no_backup'] = '$canonicalApp/no_backup'
        ..resolved[canonicalApp] = canonicalApp
        ..resolved['$canonicalApp/no_backup'] = '$canonicalApp/no_backup';
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getOutboxRoot');
        return {
          'path': '$rawApp/no_backup/mda2_activity',
          'storage_scope': 'no_backup_private',
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final platform = MethodChannelAndroidActivitySignalPlatform(
        channel: channel,
        outboxFileSystemForTesting: fs,
      );
      final first = await platform.getOutboxRoot();
      final second = await platform.getOutboxRoot();
      expect(first.path, '$canonicalApp/no_backup/mda2_activity');
      expect(second.path, first.path);
    },
  );

  group('R3 pathfix real directory boundary', () {
    late Directory scratch;
    late Directory parent;
    late Directory root;
    late MethodChannel channel;
    late MethodChannelAndroidActivitySignalPlatform platform;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    setUp(() async {
      scratch = await Directory.systemTemp.createTemp('r3_pathfix_');
      parent = Directory('${scratch.path}${Platform.pathSeparator}no_backup')
        ..createSync();
      root = Directory('${parent.path}${Platform.pathSeparator}mda2_activity');
      channel = MethodChannel('r3_pathfix_real/${scratch.path.hashCode}');
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getOutboxRoot');
        return {'path': root.path, 'storage_scope': 'no_backup_private'};
      });
      platform = MethodChannelAndroidActivitySignalPlatform(channel: channel);
    });
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      if (FileSystemEntity.typeSync(root.path, followLinks: false) ==
          FileSystemEntityType.link) {
        Link(root.path).deleteSync();
      }
      if (FileSystemEntity.typeSync(parent.path, followLinks: false) ==
          FileSystemEntityType.link) {
        Link(parent.path).deleteSync();
      }
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    });
    test(
      'missing diagnostic root is allowed without any filesystem creation',
      () async {
        final result = await platform.getOutboxRoot();
        expect(
          Directory(result.path).parent.resolveSymbolicLinksSync(),
          parent.resolveSymbolicLinksSync(),
        );
        expect(root.existsSync(), isFalse);
        expect(parent.listSync(), isEmpty);
      },
    );
    test(
      'existing diagnostic directory keeps exactly the same boundary twice',
      () async {
        root.createSync();
        final first = await platform.getOutboxRoot();
        final second = await platform.getOutboxRoot();
        expect(first.path, root.resolveSymbolicLinksSync());
        expect(second.path, first.path);
      },
    );
    test(
      'real no_backup symlink is refused before resolving its target',
      () async {
        parent.deleteSync();
        final outside = Directory(
          '${scratch.path}${Platform.pathSeparator}outside',
        )..createSync();
        Link(parent.path).createSync(outside.path);
        expect(
          FileSystemEntity.typeSync(parent.path, followLinks: false),
          FileSystemEntityType.link,
        );
        await expectLater(
          platform.getOutboxRoot(),
          throwsA(isA<AndroidActivityException>()),
        );
        expect(outside.listSync(), isEmpty);
      },
    );
    test(
      'real diagnostic root symlink is not canonicalized into acceptance',
      () async {
        final outside = Directory(
          '${scratch.path}${Platform.pathSeparator}outside',
        )..createSync();
        Link(root.path).createSync(outside.path);
        expect(
          FileSystemEntity.typeSync(root.path, followLinks: false),
          FileSystemEntityType.link,
        );
        await expectLater(
          platform.getOutboxRoot(),
          throwsA(isA<AndroidActivityException>()),
        );
        expect(outside.listSync(), isEmpty);
      },
    );
    test('file in place of diagnostic directory is refused', () async {
      File(root.path).writeAsStringSync('preserve');
      await expectLater(
        platform.getOutboxRoot(),
        throwsA(isA<AndroidActivityException>()),
      );
      expect(File(root.path).readAsStringSync(), 'preserve');
    });
    test('missing no_backup boundary is refused and never created', () async {
      parent.deleteSync();
      await expectLater(
        platform.getOutboxRoot(),
        throwsA(isA<AndroidActivityException>()),
      );
      expect(parent.existsSync(), isFalse);
    });
  });

  test(
    'R3 pathfix invalid scope and raw paths fail before filesystem access',
    () async {
      const channel = MethodChannel('r3_pathfix_invalid_input');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final fs = _BoundaryFileSystem();
      Map<String, Object?> response = {};
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final platform = MethodChannelAndroidActivitySignalPlatform(
        channel: channel,
        outboxFileSystemForTesting: fs,
      );
      for (final candidate in <Object?>[
        null,
        12,
        '',
        'relative/no_backup/mda2_activity',
        '/app/no_backup/../mda2_activity',
        '/app/./no_backup/mda2_activity',
        '/app//no_backup/mda2_activity',
        '/app/no_backup/mda2_activity/',
        '/app/no_backup/wrong',
        '/app/wrong/mda2_activity',
        '/app/no_backup/mda2_activity\u0000',
      ]) {
        response = {'path': candidate, 'storage_scope': 'no_backup_private'};
        await expectLater(
          platform.getOutboxRoot(),
          throwsA(isA<AndroidActivityException>()),
        );
      }
      for (final scope in <Object?>[null, 7, 'external', '']) {
        response = {
          'path': '/app/no_backup/mda2_activity',
          'storage_scope': scope,
        };
        await expectLater(
          platform.getOutboxRoot(),
          throwsA(isA<AndroidActivityException>()),
        );
      }
      response = {
        'path': '/app/no_backup/mda2_activity',
        'storage_scope': 'no_backup_private',
        'extra': true,
      };
      await expectLater(
        platform.getOutboxRoot(),
        throwsA(isA<AndroidActivityException>()),
      );
      expect(fs.reads, isEmpty);
    },
  );

  test(
    'R3 pathfix no_backup or root resolution escape and unreadable parent are refused',
    () async {
      const channel = MethodChannel('r3_pathfix_resolve_escape');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'path': '/app/no_backup/mda2_activity',
          'storage_scope': 'no_backup_private',
        },
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      _BoundaryFileSystem normal() => _BoundaryFileSystem()
        ..types['/app'] = FileSystemEntityType.directory
        ..types['/app/no_backup'] = FileSystemEntityType.directory
        ..resolved['/app'] = '/app'
        ..resolved['/app/no_backup'] = '/app/no_backup';
      final parentEscape = normal()
        ..resolved['/app/no_backup'] = '/outside/no_backup';
      final unreadable = normal()..resolved.remove('/app/no_backup');
      final rootEscape = normal()
        ..types['/app/no_backup/mda2_activity'] = FileSystemEntityType.directory
        ..resolved['/app/no_backup/mda2_activity'] = '/outside/mda2_activity';
      final appLink = normal()..types['/app'] = FileSystemEntityType.link;
      for (final fs in [parentEscape, unreadable, rootEscape, appLink]) {
        final platform = MethodChannelAndroidActivitySignalPlatform(
          channel: channel,
          outboxFileSystemForTesting: fs,
        );
        await expectLater(
          platform.getOutboxRoot(),
          throwsA(isA<AndroidActivityException>()),
        );
      }
    },
  );
  test(
    'R3 pathfix existing diagnostic root honors the trusted ancestor alias',
    () async {
      const channel = MethodChannel('r3_pathfix_existing_alias');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const rawApp = '/data/user/0/com.memexlab.hereiam.v3';
      const canonicalApp = '/data/data/com.memexlab.hereiam.v3';
      const rawRoot = '$rawApp/no_backup/mda2_activity';
      const canonicalRoot = '$canonicalApp/no_backup/mda2_activity';
      final fs = _BoundaryFileSystem()
        ..types[rawApp] = FileSystemEntityType.directory
        ..types['$rawApp/no_backup'] = FileSystemEntityType.directory
        ..types[rawRoot] = FileSystemEntityType.directory
        ..types[canonicalApp] = FileSystemEntityType.directory
        ..types['$canonicalApp/no_backup'] = FileSystemEntityType.directory
        ..types[canonicalRoot] = FileSystemEntityType.directory
        ..resolved[rawApp] = canonicalApp
        ..resolved['$rawApp/no_backup'] = '$canonicalApp/no_backup'
        ..resolved[rawRoot] = canonicalRoot
        ..resolved[canonicalApp] = canonicalApp
        ..resolved['$canonicalApp/no_backup'] = '$canonicalApp/no_backup'
        ..resolved[canonicalRoot] = canonicalRoot;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return {'path': rawRoot, 'storage_scope': 'no_backup_private'};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final platform = MethodChannelAndroidActivitySignalPlatform(
        channel: channel,
        outboxFileSystemForTesting: fs,
      );
      expect((await platform.getOutboxRoot()).path, canonicalRoot);
      expect((await platform.getOutboxRoot()).path, canonicalRoot);
      expect(calls, ['getOutboxRoot', 'getOutboxRoot']);
    },
  );

  test(
    'R3 pathfix pinned platform rejects a different otherwise valid canonical app root',
    () async {
      const channel = MethodChannel('r3_pathfix_pin_rejects_change');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final fs = _BoundaryFileSystem();
      for (final app in ['/app-a', '/app-b']) {
        fs.types[app] = FileSystemEntityType.directory;
        fs.types['$app/no_backup'] = FileSystemEntityType.directory;
        fs.resolved[app] = app;
        fs.resolved['$app/no_backup'] = '$app/no_backup';
      }
      var root = '/app-a/no_backup/mda2_activity';
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return {'path': root, 'storage_scope': 'no_backup_private'};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final platform = MethodChannelAndroidActivitySignalPlatform(
        channel: channel,
        outboxFileSystemForTesting: fs,
      );
      expect((await platform.getOutboxRoot()).path, root);
      root = '/app-b/no_backup/mda2_activity';
      // The second root is independently valid; only this platform's pin rejects it.
      final fresh = MethodChannelAndroidActivitySignalPlatform(
        channel: channel,
        outboxFileSystemForTesting: fs,
      );
      expect((await fresh.getOutboxRoot()).path, root);
      await expectLater(
        platform.getOutboxRoot(),
        throwsA(
          isA<AndroidActivityException>().having(
            (error) => error.code,
            'fixed code',
            'private_outbox_root_invalid',
          ),
        ),
      );
      // Both adapters expose reads only; no start, lease, or write channel call occurs.
      expect(calls, ['getOutboxRoot', 'getOutboxRoot', 'getOutboxRoot']);
    },
  );
}
