import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:path/path.dart' as path;

/// Create a system callback that masks [workingDirectory] from all paths
/// visible to the model (system prompt, skill instructions, RunJavaScript tool).
///
/// This keeps the model's view consistent with file tools that already strip
/// the workingDirectory prefix, so the model sees virtual paths like
/// `/skills/my_skill/SKILL.md` instead of real absolute paths.
SystemCallback createSystemCallbackWithWorkingDirectory(
  String workingDirectory,
) {
  final wd = workingDirectory.endsWith('/')
      ? workingDirectory.substring(0, workingDirectory.length - 1)
      : workingDirectory;

  return (
    StatefulAgent agent,
    SystemMessage? systemMessage,
    List<Tool> tools,
    List<LLMMessage> requestMessages,
  ) async {
    if (systemMessage != null) {
      final masked = _maskWorkingDirectory(systemMessage.content, wd);
      if (masked != systemMessage.content) {
        systemMessage = SystemMessage(masked);
      }
    }

    requestMessages = _maskMessagesWorkingDirectory(requestMessages, wd);
    tools = _wrapRunJavaScriptTool(tools, wd);

    return SystemCallbackResult(
      systemMessage: systemMessage,
      tools: tools,
      requestMessages: requestMessages,
    );
  };
}

String _maskWorkingDirectory(String text, String wd) {
  var result = text.replaceAll('$wd/', '/');
  result = result.replaceAll(wd, '/');
  return result;
}

List<LLMMessage> _maskMessagesWorkingDirectory(
  List<LLMMessage> messages,
  String wd,
) {
  var changed = false;
  final result = <LLMMessage>[];

  for (final msg in messages) {
    if (msg is UserMessage) {
      var msgChanged = false;
      final newContents = <UserContentPart>[];
      for (final part in msg.contents) {
        if (part is TextPart) {
          final masked = _maskWorkingDirectory(part.text, wd);
          if (masked != part.text) {
            newContents.add(TextPart(masked));
            msgChanged = true;
          } else {
            newContents.add(part);
          }
        } else {
          newContents.add(part);
        }
      }
      if (msgChanged) {
        result.add(
          UserMessage(
            newContents,
            timestamp: msg.timestamp,
            metadata: msg.metadata,
          ),
        );
        changed = true;
      } else {
        result.add(msg);
      }
    } else {
      result.add(msg);
    }
  }

  return changed ? result : messages;
}

List<Tool> _wrapRunJavaScriptTool(List<Tool> tools, String wd) {
  final idx = tools.indexWhere((t) => t.name == 'RunJavaScript');
  if (idx == -1) return tools;

  final original = tools[idx];
  final originalExec = original.executable;
  if (originalExec == null) return tools;

  final wrapped = Tool(
    name: original.name,
    description: original.description,
    parameters: original.parameters,
    namedParameters: original.namedParameters,
    parameterMode: original.parameterMode,
    executable: (String scriptPath, String? args, int? timeoutMs) {
      if (!scriptPath.startsWith(wd)) {
        if (scriptPath.startsWith('/')) {
          scriptPath =
              scriptPath == '/' ? wd : path.join(wd, scriptPath.substring(1));
        } else {
          scriptPath = path.join(wd, scriptPath);
        }
      }
      return Function.apply(originalExec, [scriptPath, args, timeoutMs]);
    },
  );

  final newTools = List<Tool>.from(tools);
  newTools[idx] = wrapped;
  return newTools;
}
