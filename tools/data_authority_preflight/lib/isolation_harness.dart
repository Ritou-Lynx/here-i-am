// ignore_for_file: curly_braces_in_flow_control_structures, empty_catches

import 'dart:convert';
import 'dart:io';

class IsolationHarness {
  static const supportedSchemaVersion = 1;
  static const expectedPurpose =
      'authority-preflight validate-only golden corpus';
  static const _files = {'manifest.json', 'corpus.json'};
  IsolationHarness({required this.repositoryRoot, required this.fixtureBase});
  final String repositoryRoot, fixtureBase;

  HarnessResult run({required String fixtureRoot, required String outputRoot}) {
    final base = _directory(fixtureBase, 'fixture base');
    final fixture = _directory(fixtureRoot, 'fixture root');
    final temp = _directory(Directory.systemTemp.path, 'system temp root');
    final output = _directory(outputRoot, 'output root');
    final repo = _directory(repositoryRoot, 'repository root');
    if (!_strictChild(fixture, base))
      throw const HarnessFailure(FailureClass.pathRejected,
          'fixture root must be below the managed fixture base');
    if (!_strictChild(output, temp) || _within(output, repo))
      throw const HarnessFailure(FailureClass.pathRejected,
          'output root must be a strict system-temp child outside the repository');
    _rejectLinks(fixture, 'fixture tree');
    _rejectLinks(output, 'output root');
    if (Directory(output).listSync(followLinks: false).isNotEmpty)
      throw const HarnessFailure(
          FailureClass.pathRejected, 'output root must be dedicated and empty');
    final manifest = _json(File(_join(fixture, 'manifest.json')));
    _manifest(manifest);
    final files = Directory(fixture)
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .map((f) => _relative(f.path, fixture))
        .toSet();
    final declared = (manifest['declaredFiles'] as List).cast<String>().toSet();
    if (files.length != 2 ||
        !files.containsAll(_files) ||
        declared.length != 2 ||
        !declared.containsAll(_files))
      throw const HarnessFailure(FailureClass.inputRejected,
          'fixture inputs must exactly match the declared allowlist');
    final raw = _json(File(_join(fixture, 'corpus.json')))['cases'];
    if (raw is! List || raw.length > 64)
      throw const HarnessFailure(
          FailureClass.inputRejected, 'corpus cases must be a bounded list');
    final cases = raw.map(_case).toList();
    final ids = <String, int>{};
    for (final c in cases) {
      ids.update(c.stableId, (v) => v + 1, ifAbsent: () => 1);
    }
    final findings = cases
        .map((c) => _classify(c, ids[c.stableId]! > 1))
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final report = <String, Object?>{
      'harness': 'data-authority-preflight',
      'mode': 'validate-only',
      'migrationExecuted': false,
      'schemaVersion': 1,
      'findings': findings.map((f) => f.toJson()).toList()
    };
    final bytes =
        utf8.encode('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    File(_join(output, 'report.json')).writeAsBytesSync(bytes, flush: true);
    return HarnessResult(report: report, reportBytes: bytes);
  }

  String _directory(String path, String label) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.link)
      throw HarnessFailure(
          FailureClass.pathRejected, '$label cannot be a link');
    if (type != FileSystemEntityType.directory)
      throw HarnessFailure(FailureClass.pathRejected,
          '$label must already exist as a directory');
    return Directory(path).resolveSymbolicLinksSync();
  }

  void _rejectLinks(String root, String label) {
    for (final e
        in Directory(root).listSync(recursive: true, followLinks: false)) {
      if (FileSystemEntity.typeSync(e.path, followLinks: false) ==
          FileSystemEntityType.link)
        throw HarnessFailure(
            FailureClass.pathRejected, '$label contains a link: ${e.path}');
    }
  }

  void _manifest(Map<String, dynamic> m) {
    if (m['schemaVersion'] != 1)
      throw const HarnessFailure(
          FailureClass.unsupported, 'unknown_manifest_schema_version');
    if (m['synthetic'] != true ||
        m['purpose'] != expectedPurpose ||
        m['declaredFiles'] is! List ||
        (m['declaredFiles'] as List).any((x) => x is! String))
      throw const HarnessFailure(FailureClass.inputRejected,
          'fixture manifest is not the expected synthetic preflight corpus');
  }

  Map<String, dynamic> _json(File f) {
    if (!f.existsSync() || f.lengthSync() > 128 * 1024)
      throw const HarnessFailure(FailureClass.inputRejected,
          'fixture input is missing or exceeds the size bound');
    try {
      final v = jsonDecode(f.readAsStringSync());
      if (v is Map<String, dynamic>) return v;
    } on FormatException {}
    throw HarnessFailure(FailureClass.inputRejected, 'invalid JSON: ${f.path}');
  }

  CorpusCase _case(dynamic raw) {
    if (raw is! Map<String, dynamic> ||
        raw['id'] is! String ||
        raw['stableId'] is! String ||
        raw['schemaVersion'] is! int ||
        raw['object'] is! Map<String, dynamic>)
      throw const HarnessFailure(
          FailureClass.inputRejected, 'corpus case shape is invalid');
    return CorpusCase(
        raw['id'], raw['stableId'], raw['schemaVersion'], raw['object']);
  }

  Finding _classify(CorpusCase c, bool duplicate) {
    if (c.schemaVersion != 1)
      return Finding(c.id, FailureClass.unsupported, 'unknown_schema_version');
    if (duplicate)
      return Finding(c.id, FailureClass.blocked, 'duplicate_stable_id');
    final o = c.object;
    switch (o['type']) {
      case 'card':
        return o['metadata'] is Map &&
                (o['metadata'] as Map)['memoryScope'] == 'user_truth'
            ? Finding(
                c.id, FailureClass.blocked, 'ordinary_card_marked_user_truth')
            : Finding(c.id, FailureClass.accepted, 'synthetic_card_loaded');
      case 'memory_card':
        return o['memory'] is Map &&
                (o['memory'] as Map)['explicitSource'] is Map
            ? Finding(c.id, FailureClass.accepted, 'explicit_user_truth_source')
            : Finding(c.id, FailureClass.blocked,
                'missing_explicit_user_truth_source');
      case 'source_anchor':
        final s = o['source'], v = o['version'], a = o['anchor'];
        return s is Map &&
                v is Map &&
                a is Map &&
                s['sourceId'] == a['sourceId'] &&
                v['versionId'] == a['sourceVersionId']
            ? Finding(
                c.id, FailureClass.accepted, 'source_version_anchor_consistent')
            : Finding(
                c.id, FailureClass.blocked, 'source_version_anchor_mismatch');
      case 'rich_text':
        return o['document'] is Map &&
                (o['document'] as Map)['unclassified'] is List &&
                ((o['document'] as Map)['unclassified'] as List).isNotEmpty
            ? Finding(
                c.id, FailureClass.blocked, 'unclassified_rich_text_content')
            : Finding(c.id, FailureClass.accepted, 'rich_text_classified');
      case 'metadata':
        return o['metadataValid'] == false || o['parseError'] is String
            ? Finding(c.id, FailureClass.blocked, 'invalid_metadata')
            : Finding(c.id, FailureClass.accepted, 'metadata_valid');
      case 'external_file':
        return Finding(
            c.id, FailureClass.blocked, 'external_move_or_delete_candidate');
      case 'conflict':
        return Finding(
            c.id, FailureClass.blocked, 'concurrent_edit_conflict_candidate');
      case 'dreaming':
        return Finding(c.id, FailureClass.blocked,
            'dreaming_must_not_promote_to_user_truth');
      case 'evidence':
        return Finding(c.id, FailureClass.unsupported,
            'evidence_production_schema_absent');
      case 'task_artifact':
        return o['promotionAuthorized'] == true
            ? Finding(c.id, FailureClass.blocked,
                'promotion_requires_formal_schema_and_contract')
            : Finding(c.id, FailureClass.blocked,
                'task_artifact_promotion_not_authorized');
      default:
        return Finding(c.id, FailureClass.unsupported, 'unknown_object_type');
    }
  }

  bool _strictChild(String c, String p) => c != p && _within(c, p);
  bool _within(String c, String p) =>
      c == p || c.startsWith('$p${Platform.pathSeparator}');
  String _join(String l, String r) => '$l${Platform.pathSeparator}$r';
  String _relative(String p, String r) =>
      p.substring(r.length + 1).replaceAll('\\', '/');
}

class CorpusCase {
  const CorpusCase(this.id, this.stableId, this.schemaVersion, this.object);
  final String id, stableId;
  final int schemaVersion;
  final Map<String, dynamic> object;
}

enum FailureClass {
  accepted,
  blocked,
  unsupported,
  pathRejected,
  inputRejected
}

class Finding {
  const Finding(this.id, this.failureClass, this.reason);
  final String id, reason;
  final FailureClass failureClass;
  Map<String, String> toJson() =>
      {'id': id, 'class': failureClass.name, 'reason': reason};
}

class HarnessFailure implements Exception {
  const HarnessFailure(this.failureClass, this.message);
  final FailureClass failureClass;
  final String message;
  @override
  String toString() => '${failureClass.name}: $message';
}

class HarnessResult {
  const HarnessResult({required this.report, required this.reportBytes});
  final Map<String, Object?> report;
  final List<int> reportBytes;
}
