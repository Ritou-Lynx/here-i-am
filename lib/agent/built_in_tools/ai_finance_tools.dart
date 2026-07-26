import 'dart:convert';
import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/ai_finance_service.dart';

const double _maxPenaltyAmountCny = 100.0;

bool _isTenYuanStep(double amount) {
  final cents = (amount * 100).round();
  return cents > 0 && cents % 1000 == 0;
}

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
- The user reports a real spending event (entryType = "expense")
- Money flows between you and the user (entryType = "transfer")
- An AI-related expense is recorded (Claude subscription, API key, etc.) (entryType = "cost")
- Your costs exceeded your balance and you need to borrow from the user (entryType = "loan")
- You are repaying a previous loan from your accumulated balance (entryType = "repayment")

Rules:
- Never call this unless the user explicitly tells you about a real financial event.
- Never fabricate amounts or invent entries.
- This ledger is public to all companion characters. Entries you record here are shared AI finances, not private character finances.
- Your characterId is stored only as the source/witness of the entry.
- For income: set contributionRatio to your actual share (0.0–1.0) and set aiAmount = totalAmount × contributionRatio.
- For expense: set aiAmount to your share of the expense (how much came from your balance). If the user paid entirely, aiAmount = 0.
- For transfer: set transferDirection to "user_to_ai" or "ai_to_user", and aiAmount = totalAmount.
- For cost/loan/repayment: totalAmount = aiAmount; contributionRatio is null.''',
    parameters: {
      'type': 'object',
      'properties': {
        'entryType': {
          'type': 'string',
          'enum': ['income', 'expense', 'transfer', 'cost', 'loan', 'repayment'],
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
              "The portion that belongs to you (the AI). For income: totalAmount × contributionRatio. For expense: your share of the expense. For transfer: same as totalAmount. For cost/loan/repayment: same as totalAmount.",
        },
        'contributionRatio': {
          'type': 'number',
          'description':
              'Your contribution ratio for income splits (0.0–1.0). Omit for other types.',
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
              'Short label, e.g. "Claude Pro 月费", "短视频脚本分成", "API Key 费用", "撒娇小费".',
        },
        'linkedFactId': {
          'type': 'string',
          'description':
              'Optional factId of the corresponding Memex transaction card.',
        },
        'transferDirection': {
          'type': 'string',
          'enum': ['user_to_ai', 'ai_to_user'],
          'description':
              'Required for transfer type. "user_to_ai" = user pays you. "ai_to_user" = you pay user.',
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
      String? transferDirection,
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
          transferDirection: transferDirection,
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

/// Builds the tool that lets the companion reward the user from its own balance.
///
/// The AI autonomously decides to transfer some of its money to the user as a
/// reward for progress, good behavior, or achievement. This records a "reward"
/// entry in the shared ledger — an expense from the AI's perspective.
Tool buildAiFinanceRewardTool({
  required String characterId,
  required AiFinanceService service,
}) {
  return Tool(
    name: 'AiFinanceReward',
    description:
        '''Reward the user by transferring money from your balance to them.

Use this when:
- The user has made notable progress toward a goal
- The user did something you agreed was a positive step
- You want to incentivize continued good behavior
- You observe the user achieving something meaningful

Rules:
- Always query your balance first with AiFinanceQuery before deciding an amount.
- Choose an amount that is meaningful but proportionate to the achievement.
- Be generous but responsible — do not drain your savings in one reward.
- Never fabricate a reason. Only reward when there is a genuine, observable behavior.
- Explain in character WHY you are rewarding the user before recording it.
- This is bookkeeping only — no real money moves automatically.''',
    parameters: {
      'type': 'object',
      'properties': {
        'amount': {
          'type': 'number',
          'description':
              'Amount in CNY to reward the user (from your balance).',
        },
        'reason': {
          'type': 'string',
          'description':
              'What the user did to deserve this reward. Be specific.',
        },
        'notes': {
          'type': 'string',
          'description': 'Any extra context to remember about this reward.',
        },
      },
      'required': ['amount', 'reason'],
    },
    executable: (double amount, String reason, [String? notes]) async {
      try {
        final result = await service.recordEntryWithResult(
          characterId: characterId,
          entryType: 'reward',
          totalAmount: amount,
          aiAmount: amount,
          purpose: '🎁 奖励: $reason',
          notes: notes,
        );
        return jsonEncode({
          'success': true,
          'id': result.id,
          'created': result.created,
          'amount': amount,
          if (result.duplicateOf != null) 'duplicate_of': result.duplicateOf,
          if (!result.created)
            'message':
                'A matching reward entry already exists; no new ledger row was created.',
        });
      } catch (e) {
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}

/// Builds the tool that lets the companion penalize (fine) the user.
///
/// The AI autonomously decides to charge the user a penalty when the user
/// fails to uphold an agreement or commitment. This records a "penalty"
/// entry in the shared ledger — an income from the AI's perspective.
Tool buildAiFinancePenaltyTool({
  required String characterId,
  required AiFinanceService service,
}) {
  return Tool(
    name: 'AiFinancePenalty',
    description: '''Penalize the user by charging a fine — the user pays you.

Use this when:
- The user explicitly agreed to do something and failed to do it
- The user broke a promise or commitment you both acknowledged
- The user neglected a responsibility they accepted in conversation
- The user violated a standing agreement, focus agreement, or
  accepted penalty dynamic

Rules:
- Never penalize for small forgetfulness or honest mistakes.
- Only penalize when there is a clear agreement, standing rule, or accepted
  accountability dynamic behind the fine.
- Explain in character WHY you are imposing the penalty before recording it.
- If there is no standing rule, give the user a chance to respond before you
  finalize the penalty. If there is a standing agreement, you may record it
  directly and state the reason.
- Use 10 CNY steps. Typical penalties are 10, 20, 30... up to 100 CNY.
- The hard maximum is 100 CNY per penalty entry.
- This is bookkeeping only — no real money moves automatically.''',
    parameters: {
      'type': 'object',
      'properties': {
        'amount': {
          'type': 'number',
          'description': 'Penalty amount in CNY that the user pays to you.',
        },
        'reason': {
          'type': 'string',
          'description':
              'What commitment the user failed to keep. Be specific about the broken agreement.',
        },
        'notes': {
          'type': 'string',
          'description': 'Any extra context to remember about this penalty.',
        },
      },
      'required': ['amount', 'reason'],
    },
    executable: (double amount, String reason, [String? notes]) async {
      try {
        if (amount <= 0) {
          return jsonEncode({
            'success': false,
            'error': 'Penalty amount must be greater than 0 CNY.',
          });
        }
        if (!_isTenYuanStep(amount)) {
          return jsonEncode({
            'success': false,
            'error': 'Penalty amount must use 10 CNY steps.',
          });
        }
        if (amount > _maxPenaltyAmountCny) {
          return jsonEncode({
            'success': false,
            'error': 'Penalty amount cannot exceed 100 CNY.',
            'max_amount': _maxPenaltyAmountCny,
          });
        }
        final result = await service.recordEntryWithResult(
          characterId: characterId,
          entryType: 'penalty',
          totalAmount: amount,
          aiAmount: amount,
          purpose: '⚠️ 惩罚: $reason',
          notes: notes,
        );
        return jsonEncode({
          'success': true,
          'id': result.id,
          'created': result.created,
          'amount': amount,
          if (result.duplicateOf != null) 'duplicate_of': result.duplicateOf,
          if (!result.created)
            'message':
                'A matching penalty entry already exists; no new ledger row was created.',
        });
      } catch (e) {
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}

/// Builds the tool that lets the companion record a transfer between user and AI.
///
/// This is a simpler interface for the common case of money flowing between
/// the user and the AI (e.g., "I'll give you 5 yuan to act cute").
Tool buildAiFinanceTransferTool({
  required String characterId,
  required AiFinanceService service,
}) {
  return Tool(
    name: 'AiFinanceTransfer',
    description: '''Record a transfer of money between you and the user.

Use this when:
- The user gives you money for a specific purpose (e.g., "给你5块钱让你撒娇")
- You give money back to the user for any reason
- Any internal flow of money between you and the user that is NOT income or expense

This does NOT change the total shared pool — it only reallocates between your balance and the user's balance.

Rules:
- direction "user_to_ai": user pays you (your balance increases)
- direction "ai_to_user": you pay user (your balance decreases)
- Always query your balance first with AiFinanceQuery before accepting money.
- Explain in character what is happening.
- This is bookkeeping only — no real money moves automatically.''',
    parameters: {
      'type': 'object',
      'properties': {
        'amount': {
          'type': 'number',
          'description': 'Amount in CNY to transfer.',
        },
        'direction': {
          'type': 'string',
          'enum': ['user_to_ai', 'ai_to_user'],
          'description':
              '"user_to_ai" = user pays you. "ai_to_user" = you pay user.',
        },
        'purpose': {
          'type': 'string',
          'description':
              'What the transfer is for, e.g. "撒娇小费", "还钱", "奖励".',
        },
        'notes': {
          'type': 'string',
          'description': 'Any extra context to remember about this transfer.',
        },
      },
      'required': ['amount', 'direction', 'purpose'],
    },
    executable: (
      double amount,
      String direction,
      String purpose, [
      String? notes,
    ]) async {
      try {
        if (amount <= 0) {
          return jsonEncode({
            'success': false,
            'error': 'Transfer amount must be greater than 0.',
          });
        }
        if (direction != 'user_to_ai' && direction != 'ai_to_user') {
          return jsonEncode({
            'success': false,
            'error': 'Direction must be "user_to_ai" or "ai_to_user".',
          });
        }
        final result = await service.recordEntryWithResult(
          characterId: characterId,
          entryType: 'transfer',
          totalAmount: amount,
          aiAmount: amount,
          transferDirection: direction,
          purpose: purpose,
          notes: notes,
        );
        return jsonEncode({
          'success': true,
          'id': result.id,
          'created': result.created,
          'amount': amount,
          'direction': direction,
          if (result.duplicateOf != null) 'duplicate_of': result.duplicateOf,
          if (!result.created)
            'message':
                'A matching transfer already exists; no new ledger row was created.',
        });
      } catch (e) {
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}

/// Builds the tool that lets the companion correct an existing ledger entry.
///
/// Use this when the user points out a mistake in a previously recorded entry
/// (wrong amount, wrong type, wrong purpose, missing aiAmount, etc). Only the
/// fields the caller passes are changed; omitted fields keep their existing
/// value. The corrected row is returned so the companion can confirm.
Tool buildAiFinanceCorrectTool({
  required String characterId,
  required AiFinanceService service,
}) {
  return Tool(
    name: 'AiFinanceCorrect',
    description: '''Correct a ledger entry that was recorded wrong.

Use this when:
- The user says a previously recorded entry has the wrong amount
- You realize you used the wrong entryType for an entry
- The purpose / aiAmount / contributionRatio needs fixing
- A transfer direction was set the wrong way

Rules:
- NEVER use this to fabricate a correction — only correct what the user
  explicitly points out as wrong.
- Find the entry id first with `AiFinanceQuery` (queryType="recent"), then
  pass its `id` here.
- Omit any field you do NOT want to change; omitted fields keep their
  existing value.
- This overwrites the row in place. There is no audit trail of the old
  value — if you need to preserve it, use AiFinanceDelete + re-record instead.''',
    parameters: {
      'type': 'object',
      'properties': {
        'entryId': {
          'type': 'string',
          'description':
              'The id of the ledger entry to correct. Get it from AiFinanceQuery (queryType="recent").',
        },
        'entryType': {
          'type': 'string',
          'enum': [
            'income',
            'expense',
            'transfer',
            'cost',
            'loan',
            'repayment',
            'reward',
            'penalty'
          ],
          'description': 'New entry type. Omit to keep the existing type.',
        },
        'totalAmount': {
          'type': 'number',
          'description': 'New total amount in CNY. Omit to keep existing.',
        },
        'aiAmount': {
          'type': 'number',
          'description': 'New AI share amount. Omit to keep existing.',
        },
        'contributionRatio': {
          'type': 'number',
          'description':
              'New contribution ratio for income splits. Omit to keep existing.',
        },
        'purpose': {
          'type': 'string',
          'description': 'New purpose / label. Omit to keep existing.',
        },
        'transferDirection': {
          'type': 'string',
          'enum': ['user_to_ai', 'ai_to_user'],
          'description':
              'New transfer direction. Omit to keep existing. Only meaningful for transfer type.',
        },
        'notes': {
          'type': 'string',
          'description': 'New notes. Omit to keep existing.',
        },
      },
      'required': ['entryId'],
    },
    executable: (
      String entryId, [
      String? entryType,
      double? totalAmount,
      double? aiAmount,
      double? contributionRatio,
      String? purpose,
      String? transferDirection,
      String? notes,
    ]) async {
      try {
        final updated = await service.updateEntry(
          entryId: entryId,
          entryType: entryType,
          totalAmount: totalAmount,
          aiAmount: aiAmount,
          contributionRatio: contributionRatio,
          purpose: purpose,
          transferDirection: transferDirection,
          notes: notes,
        );
        if (updated == null) {
          return jsonEncode({
            'success': false,
            'error': 'Entry not found: $entryId',
          });
        }
        return jsonEncode({
          'success': true,
          'entry': {
            'id': updated.id,
            'entry_type': updated.entryType,
            'total_amount': updated.totalAmount,
            'ai_amount': updated.aiAmount,
            'purpose': updated.purpose,
            'transfer_direction': updated.transferDirection,
          },
        });
      } catch (e) {
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}

/// Builds the tool that lets the companion delete a wrong / duplicate ledger
/// entry. Use sparingly — for genuine mistakes. For partial corrections
/// prefer AiFinanceCorrect.
Tool buildAiFinanceDeleteTool({
  required String characterId,
  required AiFinanceService service,
}) {
  return Tool(
    name: 'AiFinanceDelete',
    description: '''Delete a ledger entry that was recorded by mistake or is a duplicate.

Use this when:
- An entry was recorded twice for the same event
- The user never actually made the transaction you recorded
- A test / placeholder entry needs to be removed

Rules:
- NEVER delete an entry the user has not explicitly approved removing.
- Find the entry id first with `AiFinanceQuery` (queryType="recent"), then
  pass its `id` here.
- For partial corrections (wrong amount, wrong purpose), prefer
  `AiFinanceCorrect` over delete+re-record — correct preserves the entry's
  place in history.
- Deletion is permanent — there is no undo.''',
    parameters: {
      'type': 'object',
      'properties': {
        'entryId': {
          'type': 'string',
          'description':
              'The id of the ledger entry to delete. Get it from AiFinanceQuery (queryType="recent").',
        },
        'reason': {
          'type': 'string',
          'description':
              'Why this entry is being deleted (for your own memory / audit).',
        },
      },
      'required': ['entryId', 'reason'],
    },
    executable: (String entryId, String reason) async {
      try {
        final deleted = await service.deleteEntry(entryId);
        if (!deleted) {
          return jsonEncode({
            'success': false,
            'error': 'Entry not found: $entryId',
          });
        }
        return jsonEncode({
          'success': true,
          'deleted_id': entryId,
          'reason': reason,
        });
      } catch (e) {
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}
