import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import 'data/memory_v3/services/task_room_service.dart';
import 'data/workbench_ai/candidate/p6_r7_candidate_config.dart';
import 'data/workbench_ai/candidate/p6_r7_candidate_session_resources.dart';
import 'data/workbench_ai/candidate/p6_r7_candidate_store.dart';
import 'data/workbench_ai/candidate/p6_r7_owned_host.dart';
import 'data/workbench_ai/candidate/p6_r7_recovery_witness_client.dart';
import 'data/workbench_ai/product/p6_r7_product_task_binding.dart';
import 'data/workbench_ai/product/workbench_product_chat_store.dart';
import 'data/workbench_ai/product/workbench_task_product_close.dart';
import 'data/workbench_ai/product/workbench_task_product_session.dart';
import 'data/workbench_ai/workbench_conversation_coordinator.dart';
import 'data/workbench_ai/workbench_runtime_binding_store.dart';
import 'data/workbench_ai/workbench_runtime_client.dart';
import 'p6_r7_candidate_main.dart'
    show
        P6R7CandidateRecoveryStart,
        P6R7CandidateTaskBinding,
        P6R7CandidateWitnessFinalizer,
        p6R7InspectRecoveryCandidate;
import 'ui/p6_r7_candidate/widgets/p6_r7_candidate_startup.dart';
import 'ui/p6_r7_product/view_models/p6_r7_product_chat_view_model.dart';
import 'ui/p6_r7_product/widgets/p6_r7_product_app.dart';

/// Independent Debug entry. The ordinary application never imports this file.
/// Uses the original strict boot/store/witness protocol for one public task.
Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final ownedHost = P6R7OwnedHost();
  P6R7RecoveryWitnessClient? witness;
  WorkbenchTaskProductClose? preparedClose;
  runApp(P6R7CandidateStartup(
    closeOwnedHost: () async {
      // Startup can finish while an OS exit is waiting. Close all resources
      // of that prepared session even if its root never mounted.
      final close = preparedClose;
      if (close != null) return close.close();
      if (!await ownedHost.close()) return false;
      await witness?.close();
      return true;
    },
    prepare: (reportStage) async {
      reportStage(P6R7CandidateStartupStage.configurationCheck);
      final boot = P6R7OwnedHostConfiguration.parse(arguments,
          enableToken: const String.fromEnvironment('P6_R7_APP_CANDIDATE'),
          candidateRoot:
              const String.fromEnvironment('P6_R7_CANDIDATE_DATA_ROOT'),
          hostRoot: const String.fromEnvironment('P6_R7_CANDIDATE_HOST_ROOT'));
      final recovery = boot.mode == 'recover';
      witness = await P6R7RecoveryWitnessClient.connectWindows(
          P6R7RecoveryWitnessConfiguration.fromEnvironment(Platform.environment,
              expectedRole:
                  recovery ? P6R7WitnessRole.successor : P6R7WitnessRole.app));
      witness!.startKeepAlive();
      final P6R7CandidateConfiguration config;
      if (recovery) {
        final inspection = p6R7InspectRecoveryCandidate(boot);
        config = await P6R7CandidateRecoveryStart<P6R7CandidateConfiguration>(
          witness: witness!,
          inspection: inspection,
          recoveryId: _randomRecoveryId(),
          bootSha256: boot.bootSha256,
          challenge: _randomHex(32),
          spawn: () {
            reportStage(P6R7CandidateStartupStage.startingOwnedHost);
            return ownedHost.start(boot);
          },
          openAfterSpawn: (origin) {
            reportStage(P6R7CandidateStartupStage.waitingForAdmission);
            return ownedHost.waitForAdmission(boot, recoveredOrigin: origin);
          },
        ).run();
      } else {
        reportStage(P6R7CandidateStartupStage.startingOwnedHost);
        await ownedHost.start(boot, witness: witness);
        reportStage(P6R7CandidateStartupStage.waitingForAdmission);
        config = await ownedHost.waitForAdmission(boot);
      }
      final firstWitness = recovery ? null : witness;
      final session =
          await _prepare(config, reportStage, witness: firstWitness);
      final finalizer = firstWitness == null
          ? null
          : P6R7CandidateWitnessFinalizer(
              closeResources: session.resources.close,
              readReceipt: () => ownedHost.readWitnessClose(boot),
              recordClosed: (receipt) => firstWitness.appClosed(
                nodeExitCode: 0,
                stdoutEof: true,
                stderrEof: true,
                stdinClosed: true,
                storeClosed: true,
                clientClosed: true,
                taskId: session.persistedTaskId(),
                scopeHash: p6R7CandidateScopeHash(boot.datasetId),
                hostClosedSha256: receipt.hostClosedSha256,
                ownerManifestSha256: receipt.ownerManifestSha256,
              ),
            );
      Future<void>? vmQuiesce;
      Future<void>? queueQuiesce;
      final close = WorkbenchTaskProductClose(
        fenceNewWork: () {
          vmQuiesce = session.viewModel.quiesce();
          queueQuiesce = session.queue.quiesce();
          // Retain the original futures and observe errors immediately while
          // the ordinary gateway closes. Neither detached nor ACK is proof.
          unawaited(vmQuiesce!.catchError((Object _) {}));
          unawaited(queueQuiesce!.catchError((Object _) {}));
        },
        closeConversation: () async {
          if (!await session.closeConversation()) return false;
          await vmQuiesce;
          return true;
        },
        joinQueueInvocations: () async {
          await queueQuiesce;
        },
        closeQueue: session.queue.lifecycleOwner.closeForHostLifecycle,
        closeOwnedHost: ownedHost.close,
        closeResources: session.resources.close,
        recordAppClosed: () async =>
            finalizer == null || (await finalizer.close()).closed,
      );
      preparedClose = close;
      return P6R7ProductApp(viewModel: session.viewModel, close: close);
    },
  ));
}

class _ProductSession {
  _ProductSession(this.resources, this.queue, this.viewModel,
      this.persistedTaskId, this.closeConversation);
  final P6R7CandidateSessionResources resources;
  final WorkbenchTaskProductSession queue;
  final P6R7ProductChatViewModel viewModel;
  final String? Function() persistedTaskId;
  final Future<bool> Function() closeConversation;
}

Future<_ProductSession> _prepare(P6R7CandidateConfiguration config,
    void Function(P6R7CandidateStartupStage) reportStage,
    {P6R7RecoveryWitnessClient? witness}) async {
  final dio = config.createClient();
  P6R7CandidateStore? store;
  try {
    reportStage(P6R7CandidateStartupStage.verifyingOwnedHost);
    await config.verifyLiveHost(dio);
    reportStage(P6R7CandidateStartupStage.preparingCandidateData);
    final candidateStore = store = await P6R7CandidateStore.open(config);
    final scopeHash = p6R7CandidateScopeHash(candidateStore.datasetId);
    if (witness != null) {
      await witness.bindOrigin(
          datasetId: candidateStore.datasetId,
          dataDirectory: config.dataDirectory,
          datasetIdentityHash: candidateStore.originIdentityHash,
          launchId: config.launchId,
          admissionSha256: config.admissionSha256,
          scopeHash: scopeHash);
    }
    final service = TaskRoomService(db: candidateStore.database);
    final persistedBinding = P6R7CandidateTaskBinding(
      persist: candidateStore.persistTaskId,
      bind: witness == null
          ? null
          : (taskId) => witness.bindTask(taskId: taskId, scopeHash: scopeHash),
    );
    final binding = P6R7ProductTaskBinding(
      conversationId: candidateStore.conversationId,
      persist: persistedBinding.persist,
      readGoal: (id) async {
        final row = await service.getTaskRoom(id);
        candidateCheck(row != null);
        return row!.goal;
      },
      register: (id, goal) async {
        final response = await dio.postUri<Object?>(
            config.baseUri.resolve('/p6/r7/product/task'),
            data: {'task_id': id, 'scope_hash': scopeHash, 'goal': goal});
        candidateCheck(response.statusCode == 200);
        p6R7ValidateProductTaskRegistration(response.data,
            taskId: id, scopeHash: scopeHash, goal: goal);
      },
    );
    // A restored exact row is validated/bound before recovery writes or tools.
    await binding.initialize(candidateStore.taskId);
    await service.restoreInterruptedTaskRoomsOnce();
    final textRuntime = WorkbenchTextTaskRuntimeClient(
        bridgeUrl: config.baseUri.toString(), dio: dio);
    final queue = WorkbenchTaskProductSession(
        taskRoomService: service,
        textRuntime: textRuntime,
        startTextSession: (manifest) =>
            textRuntime.startTextTaskSession(contextManifest: manifest),
        binding: binding,
        afterInvoke: binding.afterInvoke);
    final chat = WorkbenchProductChatStore(
        database: candidateStore.database,
        conversationId: candidateStore.conversationId);
    final conversation = WorkbenchConversationCoordinator(
      runtime: WorkbenchRuntimeClient(
          bridgeUrl:
              config.baseUri.resolve('/p6/r7/product/conversation').toString(),
          dio: dio),
      addReply: (character, content) =>
          chat.addCharacterMessage(character, content),
      bindingStore: InMemoryWorkbenchRuntimeBindingStore(),
      taskQueueTool: queue.taskQueueTool,
    );
    final viewModel = P6R7ProductChatViewModel(
        store: chat,
        coordinator: conversation,
        conversationId: candidateStore.conversationId);
    final resources = P6R7CandidateSessionResources(
        drainExecution: queue.execution.drainExecutionTails,
        closeStore: candidateStore.close,
        closeClient: () => dio.close(force: true));
    return _ProductSession(
        resources, queue, viewModel, () => candidateStore.taskId, () async {
      try {
        final response = await dio.postUri<Object?>(
            config.baseUri.resolve('/p6/r7/product/conversation/close'),
            data: <String, Object?>{});
        return response.statusCode == 200 &&
            p6R7ProductConversationClosed(
                response.data, candidateStore.conversationId);
      } on Object {
        return false;
      }
    });
  } on Object {
    try {
      await store?.close();
    } finally {
      dio.close(force: true);
    }
    rethrow;
  }
}

/// A finite strict receipt from this sealed host, never a stop ACK.
bool p6R7ProductConversationClosed(Object? value, String conversationId) {
  const keys = {
    'status',
    'conversation_id',
    'session_id',
    'turn_ids',
    'reason',
    'shared_gateway_stopped'
  };
  if (value is! Map ||
      value.length != keys.length ||
      !value.keys.every(keys.contains) ||
      jsonEncode(value).length > 65536) {
    return false;
  }
  final session = value['session_id'];
  final turns = value['turn_ids'];
  return value['status'] == 'closed' &&
      value['conversation_id'] == conversationId &&
      (session == null ||
          (session is String && session.isNotEmpty && session.length <= 256)) &&
      turns is List &&
      turns.length <= 256 &&
      turns.every((id) => id is String && id.isNotEmpty && id.length <= 256) &&
      value['reason'] == null &&
      value['shared_gateway_stopped'] == false;
}

String _randomHex(int length) {
  final random = Random.secure();
  return List.generate(
          length, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();
}

String _randomRecoveryId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
