import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/ai_purchase_service.dart';
import 'package:memex/data/services/notification_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/services/remote_task_service.dart';
import 'package:memex/data/services/taobao_service.dart';
import 'package:memex/db/app_database.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tool 1 — Budget status query
// ─────────────────────────────────────────────────────────────────────────────

/// Call this before ANY purchase to check limits and whether shopping is on.
Tool buildShoppingBudgetTool({required String characterId}) {
  final svc = AiPurchaseService(db: AppDatabase.instance);

  return Tool(
    name: 'shopping_check_budget',
    description: '''Check your current autonomous shopping budget.

ALWAYS call this before initiating a purchase. Never guess numbers from memory.

Returns:
- enabled: whether the user has enabled autonomous shopping in settings
- payment_mode: "manual_approval" (you push cashier URL, user taps once) or "auto_silent" (future)
- per_tx_limit_cny: max CNY for a single transaction
- cumulative_remaining_cny: how much budget is left in this cycle
- cumulative_spent_cny: how much you have already spent

If enabled is false, tell the user to go to Settings → 购物助手 to enable it first.''',
    parameters: {
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
    },
    executable: (_, __) async {
      try {
        return jsonEncode(await svc.getBudgetStatus());
      } catch (e) {
        return jsonEncode({'error': e.toString()});
      }
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tool 2 — Taobao product search
// ─────────────────────────────────────────────────────────────────────────────

Tool buildShoppingSearchTool() {
  final taobao = TaobaoService();

  return Tool(
    name: 'shopping_search',
    description: '''Search Taobao for products matching a query.

Use this to discover what is available before selecting an item to buy.
Returns autocomplete suggestions and a direct search URL.

Tips:
- Be specific: "无糖燕麦片 独立小包装 500g" beats "零食"
- Chinese terms work better than English on Taobao
- After searching, pick the most appropriate item and call shopping_place_order
- If the user gave you a specific product URL, you can skip search and go directly to shopping_place_order

⚠️ URL rules (very important):
- The suggestions returned here are autocomplete TITLES ONLY, they do NOT contain
  product IDs or product page URLs. Do not invent or guess any
  `item.taobao.com/item.htm?id=...` URL — such URLs will 404.
- If the user did not give you a specific product URL, you MUST pass
  the `search_url` from this response as `product_url` to shopping_place_order.
  Hermes will browse that search page and pick a real product to buy.
- Never fabricate URLs. Only ever pass through either the user-provided
  product URL or the `search_url` returned here.''',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': 'Search terms in Chinese (e.g. "日式燕麦片 独立包装")',
        },
        'max_results': {
          'type': 'integer',
          'description': 'Max suggestions to return (default 6, max 10)',
        },
      },
      'required': ['query'],
    },
    executable: (String query, [int? maxResults]) async {
      try {
        final limit = (maxResults ?? 6).clamp(1, 10);
        final suggestions =
            await taobao.searchSuggestions(query: query, limit: limit);
        return jsonEncode({
          'query': query,
          'search_url': taobao.buildSearchUrl(query),
          'suggestions': suggestions,
          'note':
              'Suggestions are Taobao autocomplete titles. '
              'Prices are not available via this API. '
              'Use search_url for full price/review data, '
              'or ask the user if they have a specific product in mind.',
        });
      } catch (e) {
        return jsonEncode({'error': 'Search failed: $e'});
      }
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tool 3 — Place order / initiate purchase
// ─────────────────────────────────────────────────────────────────────────────

Tool buildShoppingPlaceOrderTool({
  required String characterId,
  required String? characterName,
  RemoteTaskService? remoteTaskService,
}) {
  final svc = AiPurchaseService(db: AppDatabase.instance);

  return Tool(
    name: 'shopping_place_order',
    description: "Initiate a purchase on Taobao on the user's behalf.\n\n"
        "This tool enforces all budget and safety limits — it will abort "
        "automatically if the price exceeds per-transaction or cumulative limits.\n\n"
        "What it does:\n"
        "1. Hard budget + whitelist check (throws if violated — you MUST stop there)\n"
        "2. Creates a purchase log entry for full traceability\n"
        "3. Sends the user a chat message and push notification with the product details\n\n"
        "v1 limitation: Autonomous Taobao checkout (add-to-cart → payment link) requires "
        "browser automation not yet implemented. After calling this tool, tell the user: "
        "你在淘宝下单完成后，把收银台链接发给我，我来帮你完成支付宝付款推送。\n\n"
        "REQUIRED pre-conditions:\n"
        "- Call shopping_check_budget first and verify it is enabled\n"
        "- Only call for physical goods on Taobao — never for transfers, top-ups, subscriptions, or virtual items\n"
        "- Tell the user what you plan to buy BEFORE calling this\n\n"
        "Safety rules (enforced in code, not just by you):\n"
        "- Platform must be 'taobao' — no other platforms in v1\n"
        "- Product title is screened for blocked keywords (transfers, crypto, subscriptions, etc.)\n"
        "- Price must fit within per-transaction AND cumulative limits",
    parameters: {
      'type': 'object',
      'properties': {
        'user_instruction': {
          'type': 'string',
          'description':
              "The user's original purchase request (verbatim or close summary)",
        },
        'product_title': {
          'type': 'string',
          'description': 'The specific product you selected (be descriptive)',
        },
        'product_url': {
          'type': 'string',
          'description':
              'Taobao product page URL or search URL for this product. '
              'CRITICAL: only ever pass through a URL the user gave you or the '
              '`search_url` returned by shopping_search. NEVER fabricate or guess '
              'an `item.taobao.com/item.htm?id=...` URL — the suggest API does not '
              'return product IDs and any such URL will be a 404. If in doubt, '
              'pass the search URL (https://s.taobao.com/search?q=...) so Hermes '
              'can browse the search results and pick a real item.',
        },
        'estimated_price_cny': {
          'type': 'number',
          'description':
              'Estimated price in CNY — used for budget check. '
              'If you do not know exact price, use an upper-bound estimate from similar listings.',
        },
      },
      'required': [
        'user_instruction',
        'product_title',
        'product_url',
        'estimated_price_cny',
      ],
    },
    executable: (
      String userInstruction,
      String productTitle,
      String productUrl,
      double estimatedPriceCny,
    ) async {
      try {
        // 1. Budget + whitelist check
        await svc.checkBudget(
          amountCny: estimatedPriceCny,
          platform: 'taobao',
          productTitle: productTitle,
        );

        final budgetStatus = await svc.getBudgetStatus();
        final paymentMode =
            (budgetStatus['payment_mode'] as String?) ?? 'manual_approval';

        // 2. Create purchase log
        final logId = await svc.createPurchaseLog(
          characterId: characterId,
          userInstruction: userInstruction,
          paymentMode: paymentMode,
        );
        await svc.updatePurchaseStatus(
          id: logId,
          status: 'selected',
          productTitle: productTitle,
          productUrl: productUrl,
          priceCny: estimatedPriceCny,
        );

        // 3. Enqueue to Supabase for Hermes to execute (fire-and-forget)
        var remoteQueued = false;
        if (remoteTaskService != null) {
          try {
            remoteQueued = await remoteTaskService.enqueueTask(
              id: logId,
              characterId: characterId,
              instruction: userInstruction,
              budgetCny: estimatedPriceCny,
              productHint: productTitle,
              productUrl: productUrl,
            );
          } catch (_) {
            // Don't fail the local operation if Supabase is unreachable.
          }
        }

        // 4. Push notification + chat message
        final priceStr = '¥${estimatedPriceCny.toStringAsFixed(2)}';
        final notifTitle = characterName ?? '购物助手';
        final notifBody = '我帮你选好了！「$productTitle」约 $priceStr，点击查看商品。';

        await NotificationService.instance.showAgentNotification(
          title: notifTitle,
          body: notifBody,
          payload: 'shopping:$logId',
        );

        try {
          final chatMsg = remoteQueued
              ? '我在淘宝帮你找到了 「$productTitle」，约 $priceStr。\n\n'
                  '🛒 $productUrl\n\n'
                  '已把任务发给电脑端 Hermes，它会自动完成下单和支付推送。\n'
                  '稍等片刻，下单完成后我会通知你授权付款～\n'
                  '_（购物记录 ID：$logId）_'
              : '我在淘宝帮你找到了 「$productTitle」，约 $priceStr。\n\n'
                  '🛒 $productUrl\n\n'
                  '你下单后把**支付宝收银台链接**发给我，我来帮你推送付款请求～\n'
                  '_（购物记录 ID：$logId）_';
          await PersonaChatService.instance.addCharacterMessage(
            characterId,
            chatMsg,
            timestamp: DateTime.now(),
            isRead: false,
          );
        } catch (_) {}

        return jsonEncode({
          'success': true,
          'purchase_log_id': logId,
          'product_title': productTitle,
          'estimated_price_cny': estimatedPriceCny,
          'payment_mode': paymentMode,
          'status': 'selected',
          'remote_queued': remoteQueued,
          'next_step': remoteQueued
              ? 'Task has been sent to Hermes on the desktop. '
                  'Call shopping_sync_status periodically to check if Hermes has '
                  'completed checkout and pushed the payment request.'
              : 'Notify user. In v1, user must complete Taobao checkout manually '
                  'and share the cashier URL. Then call shopping_push_payment.',
        });
      } on BudgetExceededError catch (e) {
        return jsonEncode({
          'success': false,
          'aborted': true,
          'reason': e.message,
          'action':
              'Inform user why you stopped. Do not retry or substitute a cheaper item without asking.',
        });
      } on WhitelistViolationError catch (e) {
        return jsonEncode({
          'success': false,
          'aborted': true,
          'reason': e.message,
          'action': 'Inform user. Do not attempt to buy this item.',
        });
      } catch (e) {
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tool 4 — Push Alipay payment request
// ─────────────────────────────────────────────────────────────────────────────

Tool buildShoppingPushPaymentTool({required String characterId}) {
  final svc = AiPurchaseService(db: AppDatabase.instance);

  return Tool(
    name: 'shopping_push_payment',
    description: "Push an Alipay payment request to the user.\n\n"
        "Call this when you have a valid Alipay cashier URL "
        "(from cashier*.alipay.com or *excashier*.alipay.com domain).\n\n"
        "The cashier URL can come from:\n"
        "- The user sharing it after manually going through Taobao checkout\n"
        "- A future automated browser checkout step (v2)\n\n"
        "What it does:\n"
        "1. Validates the cashier URL format\n"
        "2. Updates the purchase log with the confirmed price and cashier URL\n"
        "3. Deducts from the cumulative budget tracker\n"
        "4. Sends the user a push notification with the payment link\n"
        "5. Returns the cashier URL — INCLUDE IT VERBATIM in your text reply so the "
        "Alipay payment handler can detect and process it\n\n"
        "After calling this, your text reply MUST contain the cashier URL so the system "
        "can forward it to the user's Alipay app as an authorization request. "
        "The user will see a '授权付款' button in their Alipay.",
    parameters: {
      'type': 'object',
      'properties': {
        'purchase_log_id': {
          'type': 'string',
          'description': 'The ID returned by shopping_place_order',
        },
        'cashier_url': {
          'type': 'string',
          'description':
              'The Alipay cashier URL (must contain alipay.com and cashier)',
        },
        'confirmed_price_cny': {
          'type': 'number',
          'description':
              'The actual price shown in the checkout (may differ from estimate)',
        },
      },
      'required': ['purchase_log_id', 'cashier_url', 'confirmed_price_cny'],
    },
    executable: (
      String purchaseLogId,
      String cashierUrl,
      double confirmedPriceCny,
    ) async {
      final isAlipayUrl = cashierUrl.contains('alipay.com') &&
          (cashierUrl.contains('cashier') || cashierUrl.contains('excashier'));
      if (!isAlipayUrl) {
        return jsonEncode({
          'success': false,
          'error':
              'Invalid URL. Must be an Alipay cashier URL (cashier*.alipay.com or *excashier*.alipay.com).',
        });
      }

      try {
        await svc.updatePurchaseStatus(
          id: purchaseLogId,
          status: 'payment_pushed',
          cashierUrl: cashierUrl,
          priceCny: confirmedPriceCny,
        );
        await svc.recordSpend(confirmedPriceCny);

        await NotificationService.instance.showAgentNotification(
          title: '支付宝授权付款',
          body: '¥${confirmedPriceCny.toStringAsFixed(2)} — 点击完成授权付款',
          payload: cashierUrl,
        );

        return jsonEncode({
          'success': true,
          'cashier_url': cashierUrl,
          'confirmed_price_cny': confirmedPriceCny,
          'purchase_log_id': purchaseLogId,
          'status': 'payment_pushed',
          'instruction':
              'Include the cashier_url verbatim in your text reply. '
              'Example: "好的，支付宝授权链接来了：$cashierUrl — 在支付宝里点一下授权付款就好了！"',
        });
      } catch (e) {
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tool 5 — Remote status sync (Hermes → Memex)
// ─────────────────────────────────────────────────────────────────────────────

/// Polls Supabase for updates that Hermes has written back and applies them to
/// the local purchase log. Call this after placing a remote order to check
/// whether Hermes has finished the Taobao checkout / payment steps.
Tool buildShoppingStatusSyncTool({
  required String characterId,
  required RemoteTaskService remoteTaskService,
}) {
  final svc = AiPurchaseService(db: AppDatabase.instance);

  return Tool(
    name: 'shopping_sync_status',
    description: 'Poll Supabase for Hermes status updates on pending purchases.\n\n'
        'Call this after shopping_place_order when remote_queued=true, or whenever '
        'the user asks for an update on an in-progress order.\n\n'
        'Returns:\n'
        '- pending_count: how many orders are still in-flight\n'
        '- updates: list of orders whose status changed since last check\n'
        '- Each update includes: id, new_status, product, cashier_url (if ready)\n\n'
        'Status flow: queued → ordering → cashier_ready → payment_pushed → done | failed\n\n'
        'If new_status is "cashier_ready", cashier_url will be populated — '
        'call shopping_push_payment with it immediately.\n'
        'If new_status is "payment_pushed", tell the user to check their Alipay app.',
    parameters: {
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
    },
    executable: (_, __) async {
      try {
        // 1. Find pending local purchases for this character
        final pendingIds =
            await svc.getPendingPurchaseIds(characterId: characterId);
        if (pendingIds.isEmpty) {
          return jsonEncode({
            'pending_count': 0,
            'updates': [],
            'note': 'No in-flight purchases to check.',
          });
        }

        // 2. Fetch their current state from Supabase
        final remoteTasks = await remoteTaskService.getTasks(pendingIds);

        // 3. Apply any status changes to the local log
        final updates = await svc.syncFromRemoteTasks(remoteTasks);

        // 4. If a cashier URL is ready, remind Companion to push payment
        final cashierReady = updates
            .where((u) =>
                u['new_status'] == 'cashier_ready' &&
                u['cashier_url'] != null)
            .toList();

        return jsonEncode({
          'pending_count': pendingIds.length,
          'updates': updates,
          'cashier_ready_count': cashierReady.length,
          'action_required': cashierReady.isNotEmpty
              ? 'Call shopping_push_payment for each cashier_ready item.'
              : null,
        });
      } catch (e) {
        return jsonEncode({'error': 'Sync failed: $e'});
      }
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tool 6 — Purchase history
// ─────────────────────────────────────────────────────────────────────────────

Tool buildShoppingHistoryTool({required String characterId}) {
  final svc = AiPurchaseService(db: AppDatabase.instance);

  return Tool(
    name: 'shopping_history',
    description:
        'Check recent purchases you have initiated and current budget status. '
        'Use this when the user asks what you bought or how much budget is left.',
    parameters: {
      'type': 'object',
      'properties': {
        'limit': {
          'type': 'integer',
          'description': 'Max recent purchases to return (default 5)',
        },
      },
      'required': <String>[],
    },
    executable: ([int? limit]) async {
      try {
        final history = await svc.getRecentPurchases(
          characterId: characterId,
          limit: limit ?? 5,
        );
        final budget = await svc.getBudgetStatus();
        return jsonEncode({
          'budget_status': budget,
          'recent_purchases': history,
        });
      } catch (e) {
        return jsonEncode({'error': e.toString()});
      }
    },
  );
}
