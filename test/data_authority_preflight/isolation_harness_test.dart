// ignore_for_file: avoid_relative_lib_imports, curly_braces_in_flow_control_structures
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../../tools/data_authority_preflight/lib/isolation_harness.dart';

void main() {
  final repo = Directory.current.path,
      base =
          '${Directory.current.path}${Platform.pathSeparator}tools${Platform.pathSeparator}data_authority_preflight${Platform.pathSeparator}fixtures';
  final golden = '$base${Platform.pathSeparator}golden_v1';
  late IsolationHarness h;
  final temps = <Directory>[];
  Directory out() {
    final d =
        Directory.systemTemp.createTempSync('data_authority_preflight_test_');
    temps.add(d);
    return d;
  }

  Directory fixture(String n) {
    final d = Directory('$base${Platform.pathSeparator}$n')..createSync();
    for (final f in ['manifest.json', 'corpus.json'])
      File('${d.path}${Platform.pathSeparator}$f').writeAsBytesSync(
          File('$golden${Platform.pathSeparator}$f').readAsBytesSync());
    return d;
  }

  setUp(() => h = IsolationHarness(repositoryRoot: repo, fixtureBase: base));
  tearDown(() {
    for (final d in temps) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    temps.clear();
  });
  test('loads real structured synthetic corpus without migration', () {
    final before =
        File('$golden${Platform.pathSeparator}corpus.json').readAsBytesSync();
    final r = h.run(fixtureRoot: golden, outputRoot: out().path);
    expect(r.report['migrationExecuted'], false);
    expect(
        File('${temps.single.path}${Platform.pathSeparator}report.json')
            .existsSync(),
        true);
    expect(
        File('$golden${Platform.pathSeparator}corpus.json').readAsBytesSync(),
        before);
  });
  test(
      'covers structured red lights, empty values, history, rich text and task states',
      () {
    final corpus = jsonDecode(
        File('$golden${Platform.pathSeparator}corpus.json').readAsStringSync());
    final ordinary = (corpus['cases'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((item) => item['id'] == 'ordinary-card');
    expect(ordinary['object']['content']['body'], isNull);
    expect(ordinary['object']['revision']['parentRevisionId'], 'rev-1');
    final r = h.run(fixtureRoot: golden, outputRoot: out().path);
    final fs = (r.report['findings'] as List)
        .cast<Map<String, String>>()
        .map((x) => MapEntry(x['id']!, '${x['class']}:${x['reason']}'))
        .toMap();
    expect(fs['ordinary-card'], 'blocked:ordinary_card_marked_user_truth');
    expect(fs['memory-explicit'], 'accepted:explicit_user_truth_source');
    expect(fs['source-ok'], 'accepted:source_version_anchor_consistent');
    expect(fs['source-mismatch'], 'blocked:source_version_anchor_mismatch');
    expect(fs['duplicate-a'], 'blocked:duplicate_stable_id');
    expect(fs['duplicate-b'], 'blocked:duplicate_stable_id');
    expect(
        fs['richtext-unclassified'], 'blocked:unclassified_rich_text_content');
    expect(fs['task-unauthorized'],
        'blocked:task_artifact_promotion_not_authorized');
    expect(fs['task-authorized'],
        'blocked:promotion_requires_formal_schema_and_contract');
    expect(fs['unknown-schema'], 'unsupported:unknown_schema_version');
    expect(fs['unknown-object'], 'unsupported:unknown_object_type');
    expect(fs['invalid-metadata'], 'blocked:invalid_metadata');
    expect(fs['external-moved'], 'blocked:external_move_or_delete_candidate');
    expect(fs['conflict'], 'blocked:concurrent_edit_conflict_candidate');
    expect(fs['dreaming'], 'blocked:dreaming_must_not_promote_to_user_truth');
    expect(fs['evidence'], 'unsupported:evidence_production_schema_absent');
  });
  test('is byte deterministic', () {
    final a = h.run(fixtureRoot: golden, outputRoot: out().path);
    final b = h.run(fixtureRoot: golden, outputRoot: out().path);
    expect(a.reportBytes, b.reportBytes);
    expect(jsonDecode(utf8.decode(a.reportBytes))['mode'], 'validate-only');
  });
  test('rejects temp root and nonempty output', () {
    expect(
        () => h.run(fixtureRoot: golden, outputRoot: Directory.systemTemp.path),
        _failure(FailureClass.pathRejected));
    final d = out();
    File('${d.path}${Platform.pathSeparator}x').writeAsStringSync('x');
    expect(() => h.run(fixtureRoot: golden, outputRoot: d.path),
        _failure(FailureClass.pathRejected));
  });
  test('rejects manifest invariants', () {
    for (final field in ['schemaVersion', 'synthetic', 'purpose']) {
      final d = fixture('bad_$field');
      try {
        final m = jsonDecode(
            File('${d.path}${Platform.pathSeparator}manifest.json')
                .readAsStringSync()) as Map<String, dynamic>;
        m[field] = field == 'schemaVersion'
            ? 99
            : field == 'synthetic'
                ? false
                : 'wrong';
        File('${d.path}${Platform.pathSeparator}manifest.json')
            .writeAsStringSync(jsonEncode(m));
        expect(
            () => h.run(fixtureRoot: d.path, outputRoot: out().path),
            _failure(field == 'schemaVersion'
                ? FailureClass.unsupported
                : FailureClass.inputRejected));
      } finally {
        d.deleteSync(recursive: true);
      }
    }
  });
  test('rejects an undeclared extra fixture file', () {
    final d = fixture('extra_input');
    try {
      File('${d.path}${Platform.pathSeparator}unapproved.json')
          .writeAsStringSync('{}');
      expect(() => h.run(fixtureRoot: d.path, outputRoot: out().path),
          _failure(FailureClass.inputRejected));
    } finally {
      d.deleteSync(recursive: true);
    }
  });
  test('rejects link input when platform permits creating one', () {
    final d = fixture('link_input');
    try {
      File('${d.path}${Platform.pathSeparator}corpus.json').deleteSync();
      try {
        Link('${d.path}${Platform.pathSeparator}corpus.json')
            .createSync('$golden${Platform.pathSeparator}corpus.json');
      } on FileSystemException {
        markTestSkipped('platform cannot create test link');
        return;
      }
      expect(
          () => h.run(fixtureRoot: d.path, outputRoot: out().path),
          throwsA(isA<HarnessFailure>().having(
              (x) => x.failureClass, 'class', FailureClass.pathRejected)));
    } finally {
      d.deleteSync(recursive: true);
    }
  });
}

Matcher _failure(FailureClass expected) => throwsA(isA<HarnessFailure>()
    .having((failure) => failure.failureClass, 'failure class', expected));

extension E<K, V> on Iterable<MapEntry<K, V>> {
  Map<K, V> toMap() => Map<K, V>.fromEntries(this);
}
