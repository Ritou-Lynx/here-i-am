library;

import 'package:flutter/material.dart';

import 'package:memex/domain/workbench_ai/action/workbench_action_projection.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

typedef WorkbenchActionUndo = Future<void> Function(String actionId);

class WorkbenchActionCard extends StatelessWidget {
  const WorkbenchActionCard({
    super.key,
    required this.action,
    this.onUndo,
    this.undoAvailable = false,
  });

  final WorkbenchActionProjection action;
  final WorkbenchActionUndo? onUndo;
  final bool undoAvailable;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final presentation = _presentation(action.status);
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.92,
        child: DecoratedBox(
          key: ValueKey('workbench_action_${action.actionId}'),
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            border: Border.all(
              color: action.status == WorkbenchActionStatus.failed
                  ? tokens.focus.withValues(alpha: 0.55)
                  : tokens.divider,
            ),
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: tokens.textPrimary.withValues(alpha: 0.1),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 10, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(presentation.icon,
                        size: 15, color: presentation.color(tokens)),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        action.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: whiteboardUiTextStyle(
                          fontSize: 12,
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      presentation.label,
                      style: whiteboardUiTextStyle(
                        fontSize: 10,
                        color: presentation.color(tokens),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  action.summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: whiteboardUiTextStyle(
                    fontSize: 12,
                    color: tokens.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${action.selectedItemCount} 项 · ${action.groupCount} 组 · ${action.edgeCount} 条连线',
                      style: whiteboardUiTextStyle(
                        fontSize: 10,
                        color: tokens.textFaint,
                      ),
                    ),
                    const Spacer(),
                    _TextAction(
                      key: ValueKey(
                          'workbench_action_details_${action.actionId}'),
                      label: '详情',
                      onTap: () => showWorkbenchActionDetails(context, action),
                    ),
                    if (action.status == WorkbenchActionStatus.completed &&
                        undoAvailable &&
                        onUndo != null) ...[
                      const SizedBox(width: 7),
                      _TextAction(
                        key: ValueKey(
                            'workbench_action_undo_${action.actionId}'),
                        label: '撤销',
                        emphasized: true,
                        onTap: () => onUndo!(action.actionId),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showWorkbenchActionDetails(
  BuildContext context,
  WorkbenchActionProjection action,
) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭行动详情',
    barrierColor: Colors.black.withValues(alpha: 0.16),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, _, __) => Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 372,
        height: double.infinity,
        child: _WorkbenchActionDetailDrawer(action: action),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class _WorkbenchActionDetailDrawer extends StatelessWidget {
  const _WorkbenchActionDetailDrawer({required this.action});

  final WorkbenchActionProjection action;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Material(
      key: const ValueKey('workbench_action_detail_drawer'),
      color: tokens.surfaceRaised,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      action.title,
                      style: whiteboardUiTextStyle(
                        fontSize: 15,
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('workbench_action_detail_close'),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _DetailRow(
                  label: '状态', value: _presentation(action.status).label),
              _DetailRow(label: '对象', value: '${action.selectedItemCount} 项'),
              _DetailRow(
                  label: '结果',
                  value: '${action.groupCount} 组 / ${action.edgeCount} 条连线'),
              _DetailRow(label: '白板', value: action.boardId),
              if (action.tools.isNotEmpty)
                _DetailRow(label: '工具', value: action.tools.join(' → ')),
              if (action.operationBatchId != null)
                _DetailRow(label: '操作批次', value: action.operationBatchId!),
              if (action.authorizationId != null)
                _DetailRow(label: '授权', value: action.authorizationId!),
              if (action.errorCode != null)
                _DetailRow(label: '错误', value: action.errorCode!),
              const SizedBox(height: 14),
              Text(
                action.summary,
                style: whiteboardUiTextStyle(
                  fontSize: 13,
                  color: tokens.textMuted,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              Text(
                '这里只显示产品审计摘要；模型原始日志和私有路径不会进入聊天。',
                style: whiteboardUiTextStyle(
                  fontSize: 10,
                  color: tokens.textFaint,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style:
                  whiteboardUiTextStyle(fontSize: 11, color: tokens.textFaint),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style:
                  whiteboardUiTextStyle(fontSize: 11, color: tokens.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({
    super.key,
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: Text(
          label,
          style: whiteboardUiTextStyle(
            fontSize: 10,
            color: emphasized ? tokens.action : tokens.textMuted,
            fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

_ActionPresentation _presentation(WorkbenchActionStatus status) =>
    switch (status) {
      WorkbenchActionStatus.running => const _ActionPresentation(
          label: '进行中',
          icon: Icons.motion_photos_on_outlined,
          tone: _ActionTone.action,
        ),
      WorkbenchActionStatus.completed => const _ActionPresentation(
          label: '已完成',
          icon: Icons.check_circle_outline_rounded,
          tone: _ActionTone.action,
        ),
      WorkbenchActionStatus.failed => const _ActionPresentation(
          label: '未完成',
          icon: Icons.error_outline_rounded,
          tone: _ActionTone.warning,
        ),
      WorkbenchActionStatus.undone => const _ActionPresentation(
          label: '已撤销',
          icon: Icons.undo_rounded,
          tone: _ActionTone.muted,
        ),
    };

enum _ActionTone { action, warning, muted }

class _ActionPresentation {
  const _ActionPresentation({
    required this.label,
    required this.icon,
    required this.tone,
  });

  final String label;
  final IconData icon;
  final _ActionTone tone;

  Color color(DesktopWorkspaceTokens tokens) => switch (tone) {
        _ActionTone.action => tokens.action,
        _ActionTone.warning => tokens.focus,
        _ActionTone.muted => tokens.textFaint,
      };
}
