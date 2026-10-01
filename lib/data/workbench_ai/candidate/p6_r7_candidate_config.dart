import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'p6_r7_recovery_identity.dart';

const p6R7CandidateEnableToken = 'local-fixed-public-v1';
const p6R7CandidateGoal = '只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。';
const p6R7CandidateTitle = '公开文字验收';
const p6R7CandidateProfile = 'workbench_text_only_v1';
const p6R7NativeHash =
    '674f159148f47c9702a360bfb4d32fd7b37604cd453a3104a3db08dd83fd02fc';
final _hashPattern = RegExp(r'^[a-f0-9]{64}$');
final p6R7CandidateUuid = RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$');

void candidateCheck(bool condition) {
  if (!condition) throw const FormatException('candidate_admission_rejected');
}

/// Reject links/junctions and noncanonical ancestors before any file creation.
/// A candidate can only be created immediately below its explicitly bound root.
String candidateCanonicalPath(String value, {bool mayBeMissing = false}) {
  candidateCheck(value.isNotEmpty && p.isAbsolute(value));
  candidateCheck(p.normalize(value) == value && !value.startsWith(r'\\'));
  final parts = <String>[];
  var current = value;
  while (true) {
    parts.add(current);
    final parent = p.dirname(current);
    if (parent == current) break;
    current = parent;
  }
  for (final item in parts.reversed) {
    final type = FileSystemEntity.typeSync(item, followLinks: false);
    if (type == FileSystemEntityType.notFound &&
        item == value &&
        mayBeMissing) {
      continue;
    }
    candidateCheck(type == FileSystemEntityType.directory ||
        type == FileSystemEntityType.file);
    final resolved = type == FileSystemEntityType.directory
        ? Directory(item).resolveSymbolicLinksSync()
        : File(item).resolveSymbolicLinksSync();
    candidateCheck(p.equals(p.normalize(resolved), item));
  }
  return value;
}

Map<String, dynamic> candidateJson(List<int> bytes, Set<String> fields) {
  candidateCheck(bytes.length <= 8192);
  final value = P6R7StrictJson.decode(bytes);
  candidateCheck(value is Map<String, dynamic>);
  final map = value as Map<String, dynamic>;
  candidateCheck(map.length == fields.length && fields.every(map.containsKey));
  return map;
}

class P6R7CandidateConfiguration {
  P6R7CandidateConfiguration._({
    required this.dataDirectory,
    required this.admissionPath,
    required this.admissionSha256,
    required this.restart,
    required this.launchId,
    required this.baseUri,
    required this.sourceClosureSha256,
    this.recoveredOrigin,
    required String token,
  }) : _token = token;

  final String dataDirectory;
  final String admissionPath;
  final String admissionSha256;
  final bool restart;
  final String launchId;
  final Uri baseUri;
  final String sourceClosureSha256;
  // A validated origin is data only. The owned launcher must separately consume
  // its live witness permit before starting the successor host.
  final P6R7RecoveryInspection? recoveredOrigin;
  final String _token;
  bool _liveHostVerified = false;
  bool get liveHostVerified => _liveHostVerified;

  static P6R7CandidateConfiguration parse(
    List<String> args, {
    required String enableToken,
    required String candidateRoot,
    P6R7RecoveryInspection? recoveredOrigin,
  }) {
    candidateCheck(kDebugMode && enableToken == p6R7CandidateEnableToken);
    candidateCheck(args.length == 9 && args.first == '--p6-r7-app-candidate');
    final values = <String, String>{};
    for (var i = 1; i < args.length; i += 2) {
      candidateCheck(const {
            '--admission',
            '--admission-sha256',
            '--data-dir',
            '--mode'
          }.contains(args[i]) &&
          !values.containsKey(args[i]));
      values[args[i]] = args[i + 1];
    }
    candidateCheck(values.length == 4);
    final mode = values['--mode'];
    candidateCheck(mode == 'fresh' ||
        mode == 'restart' ||
        mode == 'recover' && recoveredOrigin != null);
    candidateCheck((mode == 'recover') == (recoveredOrigin != null));
    final root = candidateCanonicalPath(candidateRoot);
    candidateCheck(FileSystemEntity.isDirectorySync(root) &&
        p.basename(root) == 'p6-r7-app-data');
    final data =
        candidateCanonicalPath(values['--data-dir']!, mayBeMissing: true);
    candidateCheck(p.equals(p.dirname(data), root));
    candidateCheck(p.basename(data).startsWith('run-') &&
        p6R7CandidateUuid.hasMatch(p.basename(data).substring(4)));
    candidateCheck(mode == 'fresh'
        ? FileSystemEntity.typeSync(data, followLinks: false) ==
            FileSystemEntityType.notFound
        : FileSystemEntity.isDirectorySync(data));
    if (recoveredOrigin != null) {
      candidateCheck(recoveredOrigin.origin.canonicalDirectory == data &&
          recoveredOrigin.origin.nativeSha256 == p6R7NativeHash);
    }
    final manifest = candidateCanonicalPath(values['--admission']!);
    candidateCheck(!p.isWithin(data, manifest));
    final manifestHash = values['--admission-sha256']!;
    candidateCheck(_hashPattern.hasMatch(manifestHash));
    candidateCheck(File(manifest).lengthSync() <= 8192);
    final bytes = File(manifest).readAsBytesSync();
    candidateCheck(sha256.convert(bytes).toString() == manifestHash);
    final value = candidateJson(bytes, const {
      'schema',
      'launch_id',
      'base_uri',
      'profile',
      'source_closure_sha256',
      'native_sha256',
      'admission_token',
    });
    candidateCheck(value['schema'] == 'p6_r7_app_candidate_admission_v1' &&
        value['profile'] == p6R7CandidateProfile &&
        value['native_sha256'] == p6R7NativeHash);
    candidateCheck(value['launch_id'] is String &&
        p6R7CandidateUuid.hasMatch(value['launch_id']));
    candidateCheck(value['source_closure_sha256'] is String &&
        _hashPattern.hasMatch(value['source_closure_sha256']));
    if (recoveredOrigin != null) {
      candidateCheck(value['source_closure_sha256'] ==
          recoveredOrigin.origin.sourceClosureSha256);
    }
    candidateCheck(value['admission_token'] is String &&
        _hashPattern.hasMatch(value['admission_token']));
    candidateCheck(value['base_uri'] is String);
    final uri = Uri.parse(value['base_uri'] as String);
    candidateCheck(uri.scheme == 'http' &&
        uri.host == '127.0.0.1' &&
        uri.hasPort &&
        uri.port > 1024 &&
        uri.port <= 65535 &&
        !const {47831, 47841}.contains(uri.port) &&
        uri.userInfo.isEmpty &&
        uri.path.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        uri.toString() == 'http://127.0.0.1:${uri.port}');
    return P6R7CandidateConfiguration._(
      dataDirectory: data,
      admissionPath: manifest,
      admissionSha256: manifestHash,
      restart: mode != 'fresh',
      launchId: value['launch_id'],
      baseUri: uri,
      sourceClosureSha256: value['source_closure_sha256'],
      recoveredOrigin: recoveredOrigin,
      token: value['admission_token'],
    );
  }

  Dio createClient() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 150),
      followRedirects: false,
      maxRedirects: 0,
      responseType: ResponseType.json,
      headers: {
        'X-P6-Candidate-Token': _token,
        'X-P6-Candidate-Launch': launchId
      },
    ));
    dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => HttpClient()..findProxy = (_) => 'DIRECT');
    return dio;
  }

  Future<void> verifyLiveHost(Dio dio) async {
    _liveHostVerified = false;
    candidateCanonicalPath(admissionPath);
    candidateCheck(File(admissionPath).lengthSync() <= 8192);
    candidateCheck(
        sha256.convert(File(admissionPath).readAsBytesSync()).toString() ==
            admissionSha256);
    final random = Random.secure();
    final challenge = List.generate(32, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final response = await dio.postUri(
        baseUri.resolve('/p6/r7/candidate/attest'),
        data: {'challenge': challenge});
    candidateCheck(response.statusCode == 200);
    final value = candidateJson(utf8.encode(jsonEncode(response.data)), const {
      'schema',
      'challenge',
      'launch_id',
      'port',
      'profile',
      'source_closure_sha256',
      'native_sha256',
      'no_turn_preflight_verified',
      'ready',
    });
    candidateCheck(value['schema'] == 'p6_r7_app_candidate_attestation_v1' &&
        value['challenge'] == challenge &&
        value['launch_id'] == launchId &&
        value['port'] == baseUri.port &&
        value['profile'] == p6R7CandidateProfile &&
        value['source_closure_sha256'] == sourceClosureSha256 &&
        value['native_sha256'] == p6R7NativeHash &&
        value['no_turn_preflight_verified'] == true &&
        value['ready'] == true);
    _liveHostVerified = true;
  }
}
