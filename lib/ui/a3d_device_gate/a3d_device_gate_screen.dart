import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'a3d_device_gate_controller.dart';
import 'a3d_timing_probe.dart';

final class A3dDeviceGateApp extends StatelessWidget {
  const A3dDeviceGateApp({super.key, required this.controller});

  final A3dDeviceGateController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'MDA-2 A3-D 本地诊断',
        theme: ThemeData(colorSchemeSeed: const Color(0xFF315C49)),
        home: A3dDeviceGateScreen(controller: controller),
      );
}

final class A3dDeviceGateUnavailableApp extends StatelessWidget {
  const A3dDeviceGateUnavailableApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'diagnostic_entry_unavailable',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}

final class A3dDeviceGateScreen extends StatefulWidget {
  const A3dDeviceGateScreen({super.key, required this.controller});

  final A3dDeviceGateController controller;

  @override
  State<A3dDeviceGateScreen> createState() => _A3dDeviceGateScreenState();
}

final class _A3dDeviceGateScreenState extends State<A3dDeviceGateScreen>
    with WidgetsBindingObserver {
  var _scenario = A3dDiagnosticScenario.complete;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.setForeground(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.controller.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.setForeground(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final evidence = controller.evidence.value;
          final readiness = evidence['readiness']! as Map<String, Object?>;
          final sequence = evidence['sequence']! as Map<String, Object?>;
          final counts = evidence['counts']! as Map<String, int>;
          return Scaffold(
            appBar: AppBar(title: const Text('MDA-2 A3-D 本地诊断')),
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const _BoundaryCard(),
                const SizedBox(height: 16),
                DropdownButtonFormField<A3dDiagnosticScenario>(
                  key: const ValueKey('scenario'),
                  initialValue: _scenario,
                  decoration: const InputDecoration(labelText: '启动场景'),
                  items: [
                    for (final scenario in A3dDiagnosticScenario.values)
                      DropdownMenuItem(
                        value: scenario,
                        child: Text(scenario.label),
                      ),
                  ],
                  onChanged: controller.active || controller.busy
                      ? null
                      : (value) {
                          if (value != null) setState(() => _scenario = value);
                        },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      key: const ValueKey('start_diagnostic'),
                      onPressed:
                          controller.hasCollectorResources || controller.busy
                              ? null
                              : () => controller.beginDiagnostic(_scenario),
                      child: const Text('开始诊断'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('poll_usage'),
                      onPressed: controller.canQuery && !controller.busy
                          ? controller.pollUsage
                          : null,
                      child: const Text('查询并提取已验证事件'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('refresh_evidence'),
                      onPressed:
                          controller.busy ? null : controller.refreshEvidence,
                      child: const Text('刷新屏幕证据'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('stop_diagnostic'),
                      onPressed:
                          controller.hasCollectorResources && !controller.busy
                              ? controller.stop
                              : null,
                      child: const Text('停止并释放本次资源'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('release_orphan_owner'),
                      onPressed: controller.busy
                          ? null
                          : controller.releaseOrphanOwners,
                      child: const Text('无损释放已核实的孤立 owner'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('inject_notification_evidence_loss'),
                      onPressed: controller.active && !controller.busy
                          ? controller.debugInvalidateNotificationEvidence
                          : null,
                      child: const Text('注入通知可见性失证（非 OEM 复现）'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('inject_owner_delete_failure'),
                      onPressed:
                          controller.canInjectOwnerFailure && !controller.busy
                              ? controller.debugFailUsageOwnerDeletion
                              : null,
                      child: const Text('注入 Usage owner 删除失败并关闭资源'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('reset_diagnostic'),
                      onPressed: controller.active || controller.busy
                          ? null
                          : controller.resetDiagnosticOutbox,
                      child: const Text('显式清理诊断 outbox'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('copy_evidence'),
                      onPressed: controller.busy
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(
                                    text: controller.evidence.encode()),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('evidence_copied')),
                                );
                              }
                            },
                      child: const Text('复制最小证据'),
                    ),
                  ],
                ),
                if (controller.timingProbe != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        key: const ValueKey('timing_start'),
                        onPressed: controller.startTimingTrace,
                        child: const Text('开始时序记录'),
                      ),
                      OutlinedButton(
                        key: const ValueKey('timing_arm_manual'),
                        onPressed: () =>
                            controller.armTimingRead(A3dTimingAction.manual),
                        child: const Text('延迟下次刷新'),
                      ),
                      OutlinedButton(
                        key: const ValueKey('timing_arm_resume'),
                        onPressed: () =>
                            controller.armTimingRead(A3dTimingAction.resume),
                        child: const Text('延迟下次返回'),
                      ),
                      OutlinedButton(
                        key: const ValueKey('timing_end'),
                        onPressed: controller.endTimingTrace,
                        child: const Text('结束时序记录'),
                      ),
                    ],
                  ),
                  Text(
                    '时序：${controller.timingProbe!.recording ? "记录中" : controller.timingProbe!.sealed ? "已封口" : "关闭"}；'
                    '待延迟：${controller.timingProbe!.armed?.name ?? "无"}；一次20秒',
                  ),
                ],
                const SizedBox(height: 20),
                _StatusCard(
                  readiness: readiness,
                  usagePermission: evidence['usage_permission']! as String,
                  sequence: sequence,
                ),
                Text('状态同步：${controller.synchronization.name}'),
                Text(
                    '原生观察：${controller.nativeState} / ${controller.nativeReason}'),
                if (controller.lastResourceActionResult case final result?)
                  Text(
                    '最近资源动作：${result.label} · ${result.message}（${result.code}）',
                    key: const ValueKey('resource_action_result'),
                  ),
                for (final result in controller.resourceReleaseSummary)
                  Text(result),
                const SizedBox(height: 12),
                _CountsCard(counts: counts),
              ],
            ),
          );
        },
      );
}

final class _BoundaryCard extends StatelessWidget {
  const _BoundaryCard();

  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '仅用于 hereIAmV3 Debug 真机 Gate。binding 是 synthetic/local diagnostic，'
            '不是服务端签发；没有 sender、Core、网络、开机恢复或自动启动。'
            '点击“开始诊断”会明确 opt-in 独立 Activity 前台服务，并持续显示可停止通知；'
            '它不复用或控制 BLE、Companion、check-in。开始前不会建立授权 epoch、'
            'receiver、Usage 查询、outbox 或 sequence。',
          ),
        ),
      );
}

final class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.readiness,
    required this.usagePermission,
    required this.sequence,
  });

  final Map<String, Object?> readiness;
  final String usagePermission;
  final Map<String, Object?> sequence;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('collector readiness: ${readiness['collector']}'),
              Text('usage readiness: ${readiness['usage']}'),
              Text('screen readiness: ${readiness['screen']}'),
              const Text('系统事件完整性：未知。fresh 只表示最近有事件，不代表没有遗漏。'),
              Text('usage permission: $usagePermission'),
              Text('usage sequence: ${sequence['usage']}'),
              Text('screen sequence: ${sequence['screen']}'),
            ],
          ),
        ),
      );
}

final class _CountsCard extends StatelessWidget {
  const _CountsCard({required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in counts.entries)
                Text('${entry.key}: ${entry.value}'),
            ],
          ),
        ),
      );
}
