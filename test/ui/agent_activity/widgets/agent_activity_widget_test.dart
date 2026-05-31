import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/agent_activity_service.dart';
import 'package:memex/ui/agent_activity/widgets/agent_activity_widget.dart';

void main() {
  testWidgets(
    'saved comment activity does not stay running after its task completes',
    (tester) async {
      final message = AgentActivityMessageModel(
        id: 1,
        type: AgentActivityType.tool_call_response,
        title: 'Tool called',
        content: '## SaveComment',
        agentName: 'comment_agent',
        agentId: 'comment-agent-1',
        timestamp: DateTime(2026, 5, 31, 10),
      );

      expect(
        isAgentActivityMessageRunning(
          message: message,
          hasActiveTasks: false,
          now: DateTime(2026, 5, 31, 10, 0, 1),
        ),
        isFalse,
      );
    },
  );

  testWidgets('non-terminal activity expires when its stop event is lost',
      (tester) async {
    final message = AgentActivityMessageModel(
      id: 2,
      type: AgentActivityType.tool_call_response,
      title: 'Tool called',
      agentName: 'another_agent',
      agentId: 'agent-2',
      timestamp: DateTime(2026, 5, 31, 10),
    );

    expect(
      isAgentActivityMessageRunning(
        message: message,
        hasActiveTasks: true,
        now: DateTime(2026, 5, 31, 10, 5, 1),
      ),
      isFalse,
    );
  });
}
