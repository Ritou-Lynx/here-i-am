library;

import 'dart:convert';

import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/project_memory_service.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/workbench_ai/search/workbench_search_contract.dart';

import 'existing_search_adapters.dart';
import 'workbench_search_facade.dart';
import 'workbench_search_tool_host.dart';

typedef ProjectMemoryScopeLoader = Future<Set<String>> Function();
typedef WorkbenchSearchToolHostLoader = Future<WorkbenchSearchToolHost>
    Function();

/// Product-owned authorization for the desktop Codex read surface.
///
/// Card library and explicit User-truth search are available to this local
/// product surface. Project Memory is never granted as an open lane: only
/// project ids already admitted into the local policy-gated projection are
/// issued as opaque container refs.
class DesktopWorkbenchSearchAuthorizationFactory {
  const DesktopWorkbenchSearchAuthorizationFactory({
    required ProjectMemoryScopeLoader loadProjectedProjectIds,
  }) : _loadProjectedProjectIds = loadProjectedProjectIds;

  static const profileId = 'desktop_workbench_search_v1';

  final ProjectMemoryScopeLoader _loadProjectedProjectIds;

  Future<SearchAuthorization> build() async {
    final projectIds = await _loadProjectedProjectIds();
    return SearchAuthorization(
      profileId: profileId,
      grants: [
        SearchPermissionGrant(
          lane: SearchPermissionLane.contentLibrary,
          allContainers: true,
        ),
        SearchPermissionGrant(
          lane: SearchPermissionLane.userTruth,
          allContainers: true,
        ),
        if (projectIds.isNotEmpty)
          SearchPermissionGrant(
            lane: SearchPermissionLane.projectMemory,
            allowedContainerRefs: projectIds,
          ),
      ],
    );
  }
}

class WorkbenchRuntimeToolResult {
  const WorkbenchRuntimeToolResult({required this.success, required this.text});

  final bool success;
  final String text;
}

/// Binds the provider-neutral search host to the desktop Runtime transport.
/// Model arguments and product authorization remain separate all the way to
/// [WorkbenchSearchToolHost.invoke].
class WorkbenchRuntimeSearchTool {
  WorkbenchRuntimeSearchTool({
    required WorkbenchSearchToolHostLoader loadHost,
    required DesktopWorkbenchSearchAuthorizationFactory authorizationFactory,
  })  : _loadHost = loadHost,
        _authorizationFactory = authorizationFactory;

  factory WorkbenchRuntimeSearchTool.production({
    required AppDatabase database,
    required Future<UnifiedCardRepository> Function() loadCardRepository,
  }) {
    final memoryCards = MemoryCardQueryService(database);
    final projectMemory = ProjectMemoryService(database);
    Future<WorkbenchSearchToolHost>? cachedHost;
    Future<WorkbenchSearchToolHost> loadHost() => cachedHost ??= () async {
          final cards = await loadCardRepository();
          return WorkbenchSearchToolHost(
            WorkbenchSearchFacade(
              adapters: [
                CardLibraryWorkbenchSearchAdapter(cards),
                MemoryV3WorkbenchSearchAdapter(memoryCards),
                ProjectMemoryWorkbenchSearchAdapter(projectMemory),
              ],
            ),
          );
        }();
    return WorkbenchRuntimeSearchTool(
      loadHost: loadHost,
      authorizationFactory: DesktopWorkbenchSearchAuthorizationFactory(
        loadProjectedProjectIds: projectMemory.projectedProjectIds,
      ),
    );
  }

  final WorkbenchSearchToolHostLoader _loadHost;
  final DesktopWorkbenchSearchAuthorizationFactory _authorizationFactory;

  Map<String, dynamic> get dynamicToolDefinition =>
      WorkbenchSearchToolHost.dynamicToolDefinition;

  Future<WorkbenchRuntimeToolResult> invoke(Object? arguments) async {
    try {
      if (arguments is! Map) {
        return _invalidRequest();
      }
      final payload = Map<String, dynamic>.from(arguments);
      final authorization = await _authorizationFactory.build();
      final host = await _loadHost();
      final output = await host.invoke(payload, authorization: authorization);
      final invalid = output['status'] == 'invalid_request';
      return WorkbenchRuntimeToolResult(
        success: !invalid,
        text: jsonEncode(output),
      );
    } catch (_) {
      return const WorkbenchRuntimeToolResult(
        success: false,
        text: '{"status":"failed","error_code":"search_tool_failed"}',
      );
    }
  }

  WorkbenchRuntimeToolResult _invalidRequest() =>
      const WorkbenchRuntimeToolResult(
        success: false,
        text:
            '{"status":"invalid_request","error_code":"invalid_search_request"}',
      );
}
