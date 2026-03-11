import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/file_system_service.dart';

Future<AgentState> loadOrCreateAgentState(
    String sessionId, Map<String, dynamic>? initialMetadata) async {
  final userId = initialMetadata?['userId'] ?? 'mock_user_id';
  final stateDirPath =
      await FileSystemService.instance.getAgentStateDirectory(userId);
  final stateDir = Directory(stateDirPath);
  final storage = FileStateStorage(stateDir);
  return await storage.loadOrCreate(sessionId, initialMetadata);
}

Future<void> saveAgentState(AgentState state) async {
  final userId = state.metadata['userId'] ?? 'mock_user_id';
  final stateDirPath =
      await FileSystemService.instance.getAgentStateDirectory(userId);
  final stateDir = Directory(stateDirPath);
  final storage = FileStateStorage(stateDir);
  await storage.save(state);
}

Future<void> deleteAgentState(String userId, String sessionId) async {
  final stateDirPath =
      await FileSystemService.instance.getAgentStateDirectory(userId);
  final stateDir = Directory(stateDirPath);
  final storage = FileStateStorage(stateDir);
  await storage.delete(sessionId);
}
