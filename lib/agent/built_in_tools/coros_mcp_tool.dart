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

⚠️ CRITICAL — Sleep Date Semantics (+1 day offset):
Sleep data is attributed to the WAKE-UP date, NOT the bedtime date.
This means natural-language dates and COROS dates differ by 1 day:

  Natural language          Reality                     COROS date
  ──────────────────────────────────────────────────────────────────
  "昨晚的睡眠" (last night)  July 6 night → July 7 AM    → July 7
  "7月6日的睡眠" (July 6th)  July 6 night → July 7 AM    → July 7
  "前天晚上的睡眠"            July 5 night → July 6 AM    → July 6

CORE RULE: "X日的睡眠" in conversation = the night STARTING on X.
COROS records it under X+1 (the wake-up date).
ALWAYS add 1 day when translating a user's date to a COROS date.

Examples (assume today = July 8):
- "昨晚睡得怎么样" → query TODAY (July 8). Last night (July 7 night →
  July 8 morning) is stored under July 8.
- "前天晚上睡得怎么样" → query YESTERDAY (July 7).
- "7月5日的睡眠" → query July 6 (COROS date = stated date + 1).
- "最近一次睡眠" → query TODAY first.

For late sleepers (after midnight): the entire sleep may fall within a
single COROS date (e.g., July 8 02:00→09:00). The rule is unchanged —
"昨晚" still maps to today, because that's the night that ended this
morning.

NO-DATA RULE: If the queried COROS date has no sleep data, DO NOT fall
back to an adjacent date — that is a DIFFERENT night. Tell the user
their data hasn't synced yet.

Available COROS tools and their arguments:

- queryUserInfo — user profile (height, weight, birthday, gender). No args.
- queryDailyHealthData — daily steps, calories, HR, stress, sleep. Args: days (int), timezone (string, e.g. "Asia/Shanghai")
- querySleepData — sleep score, deep/light/REM, naps. Args: days (int), startDate (string yyyyMMdd), endDate (string yyyyMMdd), timezone (string)
- queryAvgHeartRate — daily average HR. Args: days (int), timezone (string)
- queryRestingHeartRate — daily resting HR. Args: days (int), timezone (string)
- queryStressLevel — daily stress. Args: days (int), timezone (string)
- queryHrv — HRV data. Args: days (int), timezone (string). If this tool name fails, try: queryHrvAssessment, getHrvData
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
