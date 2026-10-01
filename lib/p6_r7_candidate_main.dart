import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'data/memory_v3/services/task_room_service.dart';
import 'data/workbench_ai/candidate/p6_r7_candidate_config.dart';
import 'data/workbench_ai/candidate/p6_r7_candidate_store.dart';
import 'data/workbench_ai/candidate/p6_r7_candidate_session_resources.dart';
import 'data/workbench_ai/candidate/p6_r7_owned_host.dart';
import 'data/workbench_ai/candidate/p6_r7_recovery_identity.dart';
import 'data/workbench_ai/candidate/p6_r7_recovery_witness_client.dart';
import 'data/workbench_ai/task_queue/workbench_runtime_task_queue_tool.dart';
import 'data/workbench_ai/task_queue/workbench_task_queue_lifecycle_owner.dart';
import 'data/workbench_ai/workbench_runtime_client.dart';
import 'ui/p6_r7_candidate/view_models/p6_r7_candidate_view_model.dart';
import 'ui/p6_r7_candidate/widgets/p6_r7_candidate_app.dart';
import 'ui/p6_r7_candidate/widgets/p6_r7_candidate_startup.dart';

/// Independent debug target. Never imports ordinary main, router or services.
Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final ownedHost =
      arguments.isNotEmpty && arguments.first == '--p6-r7-owned-host-candidate'
          ? P6R7OwnedHost()
          : null;
  P6R7RecoveryWitnessClient? witness;
  runApp(P6R7CandidateStartup(
    closeOwnedHost: () async {
      if (ownedHost != null && !await ownedHost.close()) return false;
      // Startup did not finish an origin/session. EOF is an unknown witness
      // outcome; never fabricate app_closed or a recovery permission here.
      await witness?.close();
      return true;
    },
    prepare: (reportStage) async {
      final P6R7CandidateConfiguration config;
      P6R7OwnedHostConfiguration? boot;
      reportStage(P6R7CandidateStartupStage.configurationCheck);
      if (ownedHost != null) {
        boot = P6R7OwnedHostConfiguration.parse(arguments,
            enableToken: const String.fromEnvironment('P6_R7_APP_CANDIDATE'),
            candidateRoot:
                const String.fromEnvironment('P6_R7_CANDIDATE_DATA_ROOT'),
            hostRoot:
                const String.fromEnvironment('P6_R7_CANDIDATE_HOST_ROOT'));
        final recovery = boot.mode == 'recover';
        witness = await P6R7RecoveryWitnessClient.connectWindows(
            P6R7RecoveryWitnessConfiguration.fromEnvironment(
                Platform.environment,
                expectedRole: recovery
                    ? P6R7WitnessRole.successor
                    : P6R7WitnessRole.app));
        witness!.startKeepAlive();
        if (recovery) {
          // This self-consistent inspection is still untrusted data. The
          // authenticated permit must match it before it reaches open().
          final candidate = p6R7InspectRecoveryCandidate(boot);
          config = await P6R7CandidateRecoveryStart<P6R7CandidateConfiguration>(
              witness: witness!,
              inspection: candidate,
              recoveryId: _randomRecoveryId(),
              bootSha256: boot.bootSha256,
              challenge: _randomChallenge(),
              spawn: () {
                reportStage(P6R7CandidateStartupStage.startingOwnedHost);
                return ownedHost.start(boot!);
              },
              openAfterSpawn: (origin) {
                reportStage(P6R7CandidateStartupStage.waitingForAdmission);
                return ownedHost.waitForAdmission(boot!,
                    recoveredOrigin: origin);
              }).run();
        } else {
          reportStage(P6R7CandidateStartupStage.startingOwnedHost);
          await ownedHost.start(boot, witness: witness);
          reportStage(P6R7CandidateStartupStage.waitingForAdmission);
          config = await ownedHost.waitForAdmission(boot);
        }
      } else {
        config = P6R7CandidateConfiguration.parse(arguments,
            enableToken: const String.fromEnvironment('P6_R7_APP_CANDIDATE'),
            candidateRoot:
                const String.fromEnvironment('P6_R7_CANDIDATE_DATA_ROOT'));
      }
      // Generation two's role channel ended at consume. Its owned process
      // chain closes locally and cannot claim another recovery generation.
      final firstWitness = boot?.mode == 'recover' ? null : witness;
      final session =
          await _prepare(config, reportStage, witness: firstWitness);
      final finalizer = firstWitness == null
          ? null
          : P6R7CandidateWitnessFinalizer(
              closeResources: session.resources.close,
              readReceipt: () => ownedHost!.readWitnessClose(boot!),
              recordClosed: (receipt) => firstWitness.appClosed(
                  nodeExitCode: 0,
                  stdoutEof: true,
                  stderrEof: true,
                  stdinClosed: true,
                  storeClosed: true,
                  clientClosed: true,
                  taskId: session.taskId(),
                  scopeHash: p6R7CandidateScopeHash(boot!.datasetId),
                  hostClosedSha256: receipt.hostClosedSha256,
                  ownerManifestSha256: receipt.ownerManifestSha256));
      return P6R7CandidateApp(
          viewModel: session.viewModel,
          lifecycleOwner: session.lifecycleOwner,
          closeSession:
              finalizer == null ? session.resources.close : finalizer.close,
          closeOwnedHost: ownedHost == null ? null : () => ownedHost.close());
    },
  ));
}

class _CandidateSession {
  _CandidateSession(
      this.resources, this.lifecycleOwner, this.viewModel, this.taskId);
  final P6R7CandidateSessionResources resources;
  final WorkbenchTaskQueueLifecycleOwner lifecycleOwner;
  final P6R7CandidateViewModel viewModel;
  final String? Function() taskId;
}

Future<_CandidateSession> _prepare(P6R7CandidateConfiguration config,
    void Function(P6R7CandidateStartupStage) reportStage,
    {P6R7RecoveryWitnessClient? witness}) async {
  final dio = config.createClient();
  P6R7CandidateStore? store;
  try {
    reportStage(P6R7CandidateStartupStage.verifyingOwnedHost);
    await config.verifyLiveHost(dio);
    reportStage(P6R7CandidateStartupStage.preparingCandidateData);
    store = await P6R7CandidateStore.open(config);
    if (witness != null) {
      await witness.bindOrigin(
          datasetId: store.datasetId,
          dataDirectory: config.dataDirectory,
          datasetIdentityHash: store.originIdentityHash,
          launchId: config.launchId,
          admissionSha256: config.admissionSha256,
          scopeHash: p6R7CandidateScopeHash(store.datasetId));
    }
    TaskRoomService.init(store.database);
    final service = TaskRoomService.instance;
    await service.restoreInterruptedTaskRoomsOnce();
    final owner = WorkbenchTaskQueueLifecycleOwner();
    final runtime = WorkbenchTextTaskRuntimeClient(
        bridgeUrl: config.baseUri.toString(), dio: dio);
    final execution = P6R7CandidateExecution(
        service: service,
        runtime: runtime,
        startTextSession: (manifest) =>
            runtime.startTextTaskSession(contextManifest: manifest));
    owner.register(execution);
    final tool = WorkbenchRuntimeTaskQueueTool(
        loadService: () async => service,
        loadExecutionController: (_) async => execution);
    final candidateStore = store;
    final taskBinding = P6R7CandidateTaskBinding(
        persist: store.persistTaskId,
        bind: witness == null
            ? null
            : (taskId) => witness.bindTask(
                taskId: taskId,
                scopeHash: p6R7CandidateScopeHash(candidateStore.datasetId)));
    if (witness != null && store.taskId != null) {
      await taskBinding.persist(store.taskId!);
    }
    final viewModel = P6R7CandidateViewModel(
      tool: tool,
      service: service,
      lifecycleOwner: owner,
      conversationId: store.conversationId,
      initialTaskId: store.taskId,
      persistTaskId: taskBinding.persist,
    );
    final resources = P6R7CandidateSessionResources(
        drainExecution: execution.drainAfterHostClose,
        closeStore: store.close,
        closeClient: () => dio.close(force: true));
    return _CandidateSession(
        resources, owner, viewModel, () => candidateStore.taskId);
  } on Object {
    try {
      await store?.close();
    } finally {
      dio.close(force: true);
    }
    rethrow;
  }
}

/// Purely a local candidate inspection until authenticated claim matches its
/// hash. No write, host start, marker replacement or authority is issued here.
P6R7RecoveryInspection p6R7InspectRecoveryCandidate(
    P6R7OwnedHostConfiguration boot) {
  candidateCheck(boot.mode == 'recover');
  final file = File(candidateCanonicalPath(
      p.join(boot.dataDirectory, P6R7CandidateStore.markerName)));
  candidateCheck(file.lengthSync() <= 8192);
  const keys = {
    'schema',
    'dataset_id',
    'directory',
    'database',
    'admission_sha256',
    'source_closure_sha256',
    'native_sha256'
  };
  final marker = candidateJson(file.readAsBytesSync(), keys);
  final ordered = <String, Object?>{for (final key in keys) key: marker[key]};
  final candidateHash =
      sha256.convert(utf8.encode(jsonEncode(ordered))).toString();
  return P6R7CandidateStore.inspectOrigin(P6R7TrustedOrigin(
      identityHash: candidateHash,
      sourceClosureSha256: boot.closureSha256,
      nativeSha256: p6R7NativeHash,
      canonicalDirectory: boot.dataDirectory,
      datasetId: boot.datasetId));
}

String _randomChallenge() {
  final random = Random.secure();
  return List.generate(
      32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

String _randomRecoveryId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Store durability precedes the unique witness task bind. A failed bind is
/// sticky even if UI refresh calls persist again with the same task.
class P6R7CandidateTaskBinding {
  P6R7CandidateTaskBinding(
      {required Future<void> Function(String) persist,
      Future<void> Function(String)? bind})
      : _persist = persist,
        _bind = bind;
  final Future<void> Function(String) _persist;
  final Future<void> Function(String)? _bind;
  String? _taskId;
  Future<void>? _operation;
  Future<void> persist(String taskId) {
    candidateCheck(taskId.length == 36 && p6R7CandidateUuid.hasMatch(taskId));
    candidateCheck(_taskId == null || _taskId == taskId);
    _taskId = taskId;
    return _operation ??= _run(taskId);
  }

  Future<void> _run(String taskId) async {
    await _persist(taskId);
    await _bind?.call(taskId);
  }
}

/// A single control-App attempt. The inspection is not accepted as authority
/// until the live witness returns a matching permit and consumes it. Cache the
/// complete operation so even repeated callers cannot reopen after unknown.
class P6R7CandidateRecoveryStart<T> {
  P6R7CandidateRecoveryStart(
      {required this.witness,
      required this.inspection,
      required this.recoveryId,
      required this.bootSha256,
      required this.challenge,
      required this.spawn,
      required this.openAfterSpawn});
  final P6R7RecoveryWitnessClient witness;
  final P6R7RecoveryInspection inspection;
  final String recoveryId, bootSha256, challenge;
  final Future<void> Function() spawn;
  final Future<T> Function(P6R7RecoveryInspection) openAfterSpawn;
  Future<T>? _operation;
  Future<T> run() => _operation ??= _run();
  Future<T> _run() async {
    final permit = await witness.claim(
        datasetId: inspection.origin.datasetId,
        datasetIdentityHash: inspection.origin.identityHash,
        recoveryId: recoveryId,
        successorBootSha256: bootSha256,
        challenge: challenge);
    await witness.spawnSuccessorOnce(permit, spawn);
    return openAfterSpawn(inspection);
  }
}

/// Root widget calls this only after VM/owner and original host have closed.
/// A missing digest or ACK remains unknown on every later exit attempt.
class P6R7CandidateWitnessFinalizer {
  P6R7CandidateWitnessFinalizer(
      {required this.closeResources,
      required this.readReceipt,
      required this.recordClosed});
  final Future<P6R7CandidateSessionCloseResult> Function() closeResources;
  final P6R7OwnedHostWitnessReceipt Function() readReceipt;
  final Future<void> Function(P6R7OwnedHostWitnessReceipt) recordClosed;
  Future<P6R7CandidateSessionCloseResult>? _close;
  Future<P6R7CandidateSessionCloseResult> close() => _close ??= _finish();
  Future<P6R7CandidateSessionCloseResult> _finish() async {
    try {
      final result = await closeResources();
      if (!result.closed) return result;
      final receipt = readReceipt();
      await recordClosed(receipt);
      return result;
    } on Object {
      return P6R7CandidateSessionCloseResult.unknown;
    }
  }
}
