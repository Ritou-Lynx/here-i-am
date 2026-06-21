import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/services/agent_activity_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/ui/core/themes/app_colors.dart';

/// A slim capsule that appears between the chat header and message list
/// when the companion has delegated a background task.
///
/// - Collapsed: a thin strip with "AI 正在整理…" + pulsing dot
/// - Expanded (on tap): a small card showing the current task description
/// - Hidden: when no delegation tasks are active
class ChatTaskCapsule extends StatefulWidget {
  const ChatTaskCapsule({super.key});

  @override
  State<ChatTaskCapsule> createState() => _ChatTaskCapsuleState();
}

class _ChatTaskCapsuleState extends State<ChatTaskCapsule>
    with SingleTickerProviderStateMixin {
  StreamSubscription<bool>? _taskSub;
  StreamSubscription<AgentActivityMessageModel>? _activitySub;

  AgentActivityMessageModel? _latestDelegationMsg;

  late final AnimationController _pulseController;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _taskSub = LocalTaskExecutor.instance.hasActiveTasksStream.listen((active) {
      if (!mounted) return;
      if (!active && _latestDelegationMsg == null) return;
      // Keep the capsule visible until the agent_stop message auto-clears.
    });

    if (AgentActivityService.isInitialized) {
      _activitySub = AgentActivityService.instance.messageStream.listen((msg) {
        if (!mounted) return;
        if (msg.agentName == 'companion_delegation') {
          setState(() => _latestDelegationMsg = msg);
          if (msg.type == AgentActivityType.agent_stop) {
            // Auto-collapse and hide after a short delay when done
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  _expanded = false;
                  _latestDelegationMsg = null;
                });
              }
            });
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _taskSub?.cancel();
    _activitySub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  bool get _isVisible {
    if (_latestDelegationMsg != null) {
      // Keep showing until agent_stop message expires
      if (_latestDelegationMsg!.type == AgentActivityType.agent_stop) {
        return false; // auto-cleared by the timer
      }
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    final title = _latestDelegationMsg?.title ?? 'AI 正在整理…';
    final content = _latestDelegationMsg?.content ?? '';

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Collapsed strip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.companionSurface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        AppColors.companionSurfaceDeep.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, child) {
                        final opacity = 0.4 + (_pulseController.value * 0.6);
                        return Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.companionAccent
                                .withValues(alpha: opacity),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.companionText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AppColors.companionTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // Expanded detail
              if (_expanded && content.isNotEmpty)
                ChatTaskCapsuleDetail(content: content),
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
class ChatTaskCapsuleDetail extends StatelessWidget {
  const ChatTaskCapsuleDetail({
    super.key,
    required this.content,
  });

  final String content;

  @override
  Widget build(BuildContext context) {
    final maxHeight =
        (MediaQuery.sizeOf(context).height * 0.32).clamp(120.0, 260.0);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101217).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.companionSurfaceDeep.withValues(alpha: 0.4),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Text(
            content,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.companionTextMuted,
            ),
          ),
        ),
      ),
    );
  }
}
