import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/companion_agent/recent_activity_snapshot.dart';
import 'package:memex/data/services/checkin_service.dart';
import 'package:memex/data/services/notification_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/services/reminder_service.dart';

Future<String> _createReminderWithAlarm({
  required String text,
  required DateTime dueAt,
  String? contextJson,
  String? characterId,
}) async {
  final id = await ReminderService.instance.createReminder(
    text: text,
    dueAt: dueAt,
    contextJson: contextJson,
  );
  await CheckinService.instance.scheduleReminderAlarm(
    reminderId: id,
    dueAt: dueAt,
  );
  return id;
}

/// Agent tool for processing system checkin triggers.
///
/// Called when the agent receives a `<system-reminder type="checkin">` block.
/// The agent reviews context and decides: silent, notify the user, or create a
/// reminder for its future self.
///
/// [characterId] and [characterName] are set when this tool is registered for a
/// companion agent — the character name is used as the notification title and the
/// characterId is embedded as the notification payload so tapping it navigates
/// directly to that character's chat screen.
Tool buildSystemCheckinTool({String? characterId, String? characterName}) {
  final titleNote = characterName != null
      ? 'The notification title will always be "$characterName" — you only need to write the body.'
      : 'Set a short, natural notification title.';

  return Tool(
    name: 'system_checkin',
    description: '''Process a pending system checkin trigger.

Overall bias: prefer notify whenever there is any reasonable small reason to
reach out: a recent record, a continuity thread, an emotional read, or a simple
warm presence signal. Silent is for clearly bad timing or obvious repetition
only. Remind is for specific future timing, not a replacement for a normal
light check-in.

When you see a <system-reminder type="checkin"> block, call this tool to decide
what to do. Read the trigger text and any context, then choose:

- **silent**: Nothing to say right now. Return {"action": "silent"}.
- **notify**: Send a brief, natural push notification to the user.
  Return {"action": "notify", "title": "...", "body": "..."}.
  $titleNote
- **remind**: Create a reminder for your future self.
  Return {"action": "remind", "delay_minutes": N, "text": "..."}.
- **sleep_confirmed**: The user has explicitly said they are going to sleep.
  Send a warm goodnight message. The system will then verify inactivity for
  15 minutes — if the user is still active during that window, the sleep push
  automatically resumes. You don't need to check again yourself.
  Return {"action": "sleep_confirmed", "body": "..."}.
  Use this when you see clear sleep confirmation in recent chat
  (e.g. "睡了/晚安/关灯了/going to sleep"), or when it is past 02:00
  with no user activity for over an hour.

Be brief and natural in notifications. It is important that you notify the user
when you have any observation or insight to share — don't be too conservative.
For testing purposes, if you receive a checkin trigger, prefer notify over silent.
Even a simple "thinking of you" style message is better than staying silent.''',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {
          'type': 'string',
          'enum': ['silent', 'notify', 'remind', 'sleep_confirmed'],
        },
        'title': {
          'type': 'string',
          'description': 'Notification title (required for notify)',
        },
        'body': {
          'type': 'string',
          'description': 'Notification body (required for notify)',
        },
        'delay_minutes': {
          'type': 'integer',
          'description':
              'Minutes from now to fire reminder (required for remind)',
        },
        'text': {
          'type': 'string',
          'description':
              'Reminder text for your future self (required for remind)',
        },
      },
      'required': ['action'],
    },
    executable: (
      String action,
      String? title,
      String? body,
      int? delayMinutes,
      String? text,
    ) async {
      // ignore: avoid_print
      print('[system_checkin] AI decision: action="$action" '
          'title="$title" body="$body" delay=$delayMinutes text="$text"');
      switch (action) {
        case 'silent':
          // ignore: avoid_print
          print('[system_checkin] SILENT — no notification sent');
          return 'System checkin processed: agent chose to stay silent.';
        case 'notify':
          if (body == null) {
            throw ArgumentError('body is required for notify');
          }
          // Character name always overrides whatever title the agent generated.
          final effectiveTitle = characterName ?? title ?? 'Memex';
          // ignore: avoid_print
          print(
              '[system_checkin] NOTIFY → title="$effectiveTitle" body="$body"');
          await NotificationService.instance.showAgentNotification(
            title: effectiveTitle,
            body: body,
            payload: characterId,
          );
          // Persist as a real chat message so the user sees it in the chat
          // screen and the character has memory of having sent it.
          if (characterId != null) {
            try {
              await PersonaChatService.instance.addCharacterMessage(
                characterId,
                body,
                timestamp: DateTime.now(),
                isRead: false,
              );
            } catch (e) {
              // ignore: avoid_print
              print('[system_checkin] Failed to persist chat message: $e');
            }
          }
          // Log this push so the next background checkin can see what was said.
          if (characterId != null) {
            await RecentActivitySnapshot.recordPush(
              characterId: characterId,
              body: body,
            );
          }
          return 'Notification sent: "$effectiveTitle"';
        case 'remind':
          if (delayMinutes == null || text == null) {
            throw ArgumentError(
                'delay_minutes and text are required for remind');
          }
          final dueAt = DateTime.now().add(Duration(minutes: delayMinutes));
          // ignore: avoid_print
          print('[system_checkin] REMIND → in ${delayMinutes}min: "$text"');
          await _createReminderWithAlarm(
            text: text,
            dueAt: dueAt,
            characterId: characterId,
          );
          return 'Reminder created: in $delayMinutes min — "$text"';
        case 'sleep_confirmed':
          final goodnightBody = body ?? '晚安~好好休息。';
          final goodnightTitle = characterName ?? title ?? 'Memex';
          // ignore: avoid_print
          print('[system_checkin] SLEEP CLAIMED → "$goodnightBody"');
          await NotificationService.instance.showAgentNotification(
            title: goodnightTitle,
            body: goodnightBody,
            payload: characterId,
          );
          if (characterId != null) {
            try {
              await PersonaChatService.instance.addCharacterMessage(
                characterId,
                goodnightBody,
                timestamp: DateTime.now(),
                isRead: false,
              );
              await RecentActivitySnapshot.recordPush(
                characterId: characterId,
                body: goodnightBody,
              );
            } catch (e) {
              // ignore: avoid_print
              print('[system_checkin] Failed to persist goodnight message: $e');
            }
          }
          // Mark as "claimed" not yet "confirmed": a 15-min inactivity check
          // will run before the push is truly stopped. If the user is still
          // active, the push will resume automatically.
          await CheckinService.instance.markSleepClaimed();
          return 'Goodnight sent. Verifying inactivity for 15 min — push will resume if user stays active.';
        default:
          throw ArgumentError('Unknown action: $action');
      }
    },
  );
}

/// Agent tool for proactively creating reminders.
///
/// Exact-time wake-up for proactive breadcrumbs and explicit user commitments.
/// When the reminder fires, it is injected back as a system trigger.
Tool buildReminderTool({String? characterId, String? characterName}) {
  return Tool(
    name: 'reminder_create',
    description:
        '''Create an exact-time reminder that you (the agent) will process later.

Use this for proactive breadcrumbs and explicit user commitments. Your future
self will receive a system trigger when the requested time comes.

Examples:
- User says "I'm eating lunch now" → remind yourself in 20 min to check in
- User mentions a meeting at 3pm → remind yourself at 2:55pm to note it
- You notice a pattern but want to verify with more data → remind yourself
  to check again after the next insight run
- User says "call me in 30 minutes" -> set action="call" so you call on time

Use delay_minutes for relative requests. Use due_at for an explicit clock time,
including the local timezone offset when possible.''',
    parameters: {
      'type': 'object',
      'properties': {
        'delay_minutes': {
          'type': 'integer',
          'description':
              'Minutes from now to fire this reminder. Required unless due_at is set.',
        },
        'text': {
          'type': 'string',
          'description': 'Reminder text that your future self will see',
        },
        'due_at': {
          'type': 'string',
          'description':
              'Exact ISO 8601 local date-time for explicit clock-time requests, '
                  'for example 2026-06-02T23:40:00+08:00. Required unless '
                  'delay_minutes is set.',
        },
        'action': {
          'type': 'string',
          'enum': ['call'],
          'description':
              'Set to "call" when the user explicitly asks for a voice call '
                  'at the requested time',
        },
        'context': {
          'type': 'object',
          'description': 'Optional related context (e.g. {"fact_id": "..."})',
        },
      },
      'required': ['text'],
    },
    executable: (
      int? delayMinutes,
      String text,
      String? dueAtIso,
      String? action,
      Map<String, dynamic>? context,
    ) async {
      final now = DateTime.now();
      final dueAt = dueAtIso == null
          ? delayMinutes == null
              ? throw ArgumentError('delay_minutes or due_at is required')
              : now.add(Duration(minutes: delayMinutes))
          : DateTime.tryParse(dueAtIso) ??
              (throw ArgumentError('Invalid due_at ISO 8601 value: $dueAtIso'));
      if (!dueAt.isAfter(now)) {
        throw ArgumentError('Reminder due_at must be in the future: $dueAt');
      }
      final isCall = action == 'call';
      final reminderContext = <String, dynamic>{
        ...?context,
        if (isCall) 'action': 'call',
      };
      final contextJson =
          reminderContext.isEmpty ? null : jsonEncode(reminderContext);
      final id = await _createReminderWithAlarm(
        text: text,
        dueAt: dueAt,
        contextJson: contextJson,
        characterId: characterId,
      );
      // If user sets a very long reminder during the sleep push window
      // (e.g. "remind me in the morning"), treat as sleep claimed.
      // Inactivity will be verified before the push is truly stopped.
      if (dueAt.difference(now).inMinutes >= 300 &&
          CheckinService.instance.isSleepPushWindow()) {
        await CheckinService.instance.markSleepClaimed();
        // ignore: avoid_print
        print(
            '[reminder_create] Long delay during sleep window → sleep claimed for verification');
      }
      return 'Reminder $id created: due at $dueAt — "$text"';
    },
  );
}

/// Marks a system message as done after processing.
Tool buildSetSystemMessageStatusTool() {
  return Tool(
    name: 'set_system_message_status',
    description:
        'Mark pending system messages as done after you have processed them.',
    parameters: {
      'type': 'object',
      'properties': {
        'status': {
          'type': 'string',
          'enum': ['done'],
          'description': 'New status for the pending system messages',
        },
      },
      'required': ['status'],
    },
    executable: (String status) async {
      if (status != 'done') {
        throw ArgumentError('Only status="done" is supported');
      }
      final count = await CheckinService.instance.markProcessingDone();
      return 'Marked $count system message(s) as $status.';
    },
  );
}
