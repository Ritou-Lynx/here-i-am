import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/memory_v3/agents/record_organizer_agent/agent.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';

/// Actual Record Organizer extraction. Planner still receives the original
/// capture via its own scoped feed; its results are never forged on the phone.
class QuickCaptureOrganizerAdapter {
  QuickCaptureOrganizerAdapter({
    required this.client,
    required this.modelConfig,
    this.agent = const RecordOrganizerAgentV3(),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final LLMClient client;
  final ModelConfig modelConfig;
  final RecordOrganizerAgentV3 agent;
  final DateTime Function() clock;

  Future<OrganizedRecord> extract(String text) async => lifeRecordsOnly(
        await agent.organize(
          client: client,
          modelConfig: modelConfig,
          rawInput: text,
          now: clock(),
        ),
      );

  static OrganizedRecord lifeRecordsOnly(OrganizedRecord record) =>
      OrganizedRecord(
        cards: record.cards
            .where(
              (card) => !const {'task', 'schedule', 'plan'}.contains(card.type),
            )
            .toList(),
      );
}
