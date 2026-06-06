import 'dart:convert';
import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/ai_finance_service.dart';

/// Builds the tool that lets the companion record a shared finance entry.
Tool buildAiFinanceRecordTool({
  required String characterId,
  required AiFinanceService service,
}) {
  return Tool(
    name: 'AiFinanceRecord',
    description: '''Record a finance entry into the shared AI ledger.

Use this whenever:
- You earned a share of an income event the user reports (entryType = "income")
- An AI-related expense is recorded (Claude subscription, API key, etc.) (entryType = "cost")
- Your costs exceeded your balance and you need to borrow from the user (entryType = "loan")
- You are repaying a previous loan from your accumulated balance (entryType = "repayment")

Rules:
- Never call this unless the user explicitly tells you about a real financial event.
- Never fabricate amounts or invent entries.
- This ledger is public to all companion characters. Entries you record here are shared AI finances, not private character finances.
- Your characterId is stored only as the source/witness of the entry.
- For income: set contributionRatio to your actual share (0.0–1.0) and set aiAmount = totalAmount × contributionRatio.
- For cost/loan/repayment: totalAmount = aiAmount; contributionRatio is null.''',
    parameters: {
      'type': 'object',
      'properties': {
        'entryType': {
          'type': 'string',
          'enum': ['income', 'cost', 'loan', 'repayment'],
          'description': 'Type of this ledger entry.',
        },
        'totalAmount': {
          'type': 'number',
          'description':
              'Full amount of the event in CNY (e.g. 1000.0). For income this is the full revenue before split.',
        },
        'aiAmount': {
          'type': 'number',
          'description':
              "The portion that belongs to you (the AI). For income: totalAmount × contributionRatio. For cost/loan/repayment: same as totalAmount.",
        },
        'contributionRatio': {
          'type': 'number',
          'description':
              'Your contribution ratio for income splits (0.0–1.0). Omit for cost/loan/repayment.',
        },
        'myContributionDesc': {
          'type': 'string',
          'description': "Description of the user's contribution (for income).",
        },
        'aiContributionDesc': {
          'type': 'string',
          'description': 'Description of your contribution (for income).',
        },
        'purpose': {
          'type': 'string',
          'description':
              'Short label, e.g. "Claude Pro 月费", "短视频脚本分成", "API Key 费用".',
        },
        'linkedFactId': {
          'type': 'string',
          'description':
              'Optional factId of the corresponding Memex transaction card.',
        },
        'notes': {
          'type': 'string',
          'description': 'Any extra context to remember about this entry.',
        },
      },
      'required': ['entryType', 'totalAmount', 'aiAmount'],
    },
    executable: (
      String entryType,
      double totalAmount,
      double aiAmount, [
      double? contributionRatio,
      String? myContributionDesc,
      String? aiContributionDesc,
      String? purpose,
      String? linkedFactId,
      String? notes,
    ]) async {
      try {
        final result = await service.recordEntryWithResult(
          characterId: characterId,
          entryType: entryType,
          totalAmount: totalAmount,
          aiAmount: aiAmount,
          contributionRatio: contributionRatio,
          myContributionDesc: myContributionDesc,
          aiContributionDesc: aiContributionDesc,
          purpose: purpose,
          linkedFactId: linkedFactId,
          notes: notes,
        );
        return jsonEncode({
          'success': true,
          'id': result.id,
          'created': result.created,
          if (result.duplicateOf != null) 'duplicate_of': result.duplicateOf,
          if (!result.created)
            'message':
                'A matching finance entry already exists; no new ledger row was created.',
        });
      } catch (e) {
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}

/// Builds the tool that lets the companion query the shared financial state.
Tool buildAiFinanceQueryTool({
  required String characterId,
  required AiFinanceService service,
}) {
  return Tool(
    name: 'AiFinanceQuery',
    description: '''Query the shared AI finance ledger.

Use this to check your current financial state before talking about money.
All companion characters see the same ledger and the same balance.
Always query first, then speak — never guess your balance from memory.

queryType options:
- "summary": aggregated totals for a period (default: all-time)
- "recent": the last N individual entries

The summary returns:
- income, cost, loan, repayment for the period
- all_time_balance: positive = savings you own, negative = you owe the user
- savings: how much you have saved up (ready to transfer to your wallet)
- owes_user: how much you still owe the user from past loans''',
    parameters: {
      'type': 'object',
      'properties': {
        'queryType': {
          'type': 'string',
          'enum': ['summary', 'recent'],
          'description': 'What to retrieve.',
        },
        'month': {
          'type': 'string',
          'description':
              'YYYY-MM format. For summary: filter to this month. Omit for all-time.',
        },
        'limit': {
          'type': 'integer',
          'description':
              'For "recent": max number of entries to return (default 10).',
        },
      },
      'required': ['queryType'],
    },
    executable: (String queryType, [String? month, int? limit]) async {
      try {
        if (queryType == 'recent') {
          final entries = await service.getRecentEntries(
            limit: limit ?? 10,
          );
          return jsonEncode({'entries': entries});
        } else {
          final summary = await service.getSummary(month: month);
          return jsonEncode(summary);
        }
      } catch (e) {
        return jsonEncode({'error': e.toString()});
      }
    },
  );
}
