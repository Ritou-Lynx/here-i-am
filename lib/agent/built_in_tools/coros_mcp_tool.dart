import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/coros_mcp_service.dart';

/// Built-in tool that lets agents query COROS health/fitness data via MCP.
///
/// Supports all 15 COROS MCP tools. The agent picks the right tool name and
/// passes the required arguments. Results are returned as text.
Tool buildCorosMcpTool() {
  return Tool(
    name: 'coros_query',
    description: '''Query the user's COROS watch health and fitness data.

Use this tool when the user asks about their COROS data: health metrics, sleep,
heart rate, stress, workouts, training load, fitness assessment, recovery, HRV,
training schedule, devices, or user profile.

⚠️ CRITICAL — Sleep Date Semantics:
Sleep data is attributed to the WAKE-UP date, NOT the bedtime date.
- When the user asks "昨晚睡得怎么样" (how did I sleep last night) at 8 AM on
  June 7, the most recent sleep session (June 6 night → June 7 morning) is
  recorded under June 7, NOT June 6.
- Always query sleep data for TODAY first when the user asks about "昨晚"
  (last night) or "最近一次睡眠" (most recent sleep).
- If today has no sleep data (watch hasn't synced yet): DO NOT fall back to
  yesterday. Yesterday's data is the WRONG night (the night before last).
  Tell the user their sleep data hasn't synced yet and suggest syncing.
- Only query a specific past date when the user explicitly asks about that
  specific night (e.g., "前天晚上睡得怎么样" or "June 5 night").
- Example: Today is June 7, user asks "昨晚睡得怎么样" → querySleepData with
  endDate="20260607" or queryDailyHealthData with days=1 (covers today).
- Rule of thumb: "昨晚的睡眠" = the most recent completed sleep session.
  Find it by looking at today's sleep data first.

Available COROS tools and their arguments:

- queryUserInfo — user profile (height, weight, birthday, gender). No args.
- queryDailyHealthData — daily steps, calories, HR, stress, sleep. Args: days (int), timezone (string, e.g. "Asia/Shanghai")
- querySleepData — sleep score, deep/light/REM, naps. Args: days (int), startDate (string yyyyMMdd), endDate (string yyyyMMdd), timezone (string)
- queryAvgHeartRate — daily average HR. Args: days (int), timezone (string)
- queryRestingHeartRate — daily resting HR. Args: days (int), timezone (string)
- queryStressLevel — daily stress. Args: days (int), timezone (string)
- queryHrvAssessment — HRV data. Args: days (int), timezone (string)
- queryRecoveryStatus — current recovery %. No args.
- queryTrainingLoadAssessment — training load. Args: days (int)
- queryFitnessAssessmentOverview — VO2max, running level, race predictions. No args.
- queryTrainingSchedule — weekly training plan. Args: startDate (string yyyyMMdd), endDate (string yyyyMMdd), timezone (string)
- querySportRecords — workout list. Args: startDate (string), endDate (string), sportTypeCodes (list of int), limit (int), timezone (string)
- getActivityDetail — single activity detail. Args: labelId (string), sportType (int)
- analyzeActivityDetail — coach-style activity analysis. Args: labelId (string), sportType (int), focus (string)
- queryDevices — bound COROS devices. No args.

Returns the data as text from COROS MCP server.''',
    parameters: {
      'type': 'object',
      'properties': {
        'tool': {
          'type': 'string',
          'description': 'The COROS MCP tool name to call, e.g. "queryUserInfo"',
        },
        'arguments': {
          'type': 'object',
          'description':
              'Arguments to pass to the COROS tool as key-value pairs. '
              'Omit if the tool takes no arguments.',
        },
      },
      'required': ['tool'],
    },
    executable: (String tool, Map<String, dynamic>? arguments) async {
      final result = await CorosMcpService.instance.callTool(
        tool,
        arguments: arguments,
      );
      return result.text;
    },
  );
}
