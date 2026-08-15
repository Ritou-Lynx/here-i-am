/// Canvas Action Log：append-only 用户画布行为流（Huabu 借鉴 § 2）。
///
/// 隐私边界与总纲 § 2.4 一致：每条行为**只存 NodeRef（id/type/label）**，
/// 绝不存节点内容；失败请求不计数；成功计数达到阈值才触发一次
/// 压缩分析（消费端），触发即清零防重复。
///
/// 本文件只落地接口 + 内存实现（写入契约）；消费端（记忆策展器）
/// 通过 [CanvasActionConsumer] 接入，Phase 3 再接持久化与真实策展。
library;

/// 节点引用：**唯一允许记录的内容字段**。
///
/// 守卫测试保证 toJson 只包含 id/type/label 三个键。
class NodeRef {
  final String id;
  final String type;
  final String label;

  const NodeRef({required this.id, required this.type, required this.label});

  factory NodeRef.fromJson(Map<String, dynamic> json) {
    final extraKeys =
        json.keys.toSet().difference(const {'id', 'type', 'label'});
    if (extraKeys.isNotEmpty) {
      throw ArgumentError(
        'NodeRef must only carry id/type/label, got extra keys: ${extraKeys.join(", ")}',
      );
    }
    return NodeRef(
      id: json['id'] as String,
      type: json['type'] as String,
      label: json['label'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'label': label};

  @override
  bool operator ==(Object other) =>
      other is NodeRef && other.id == id && other.type == type;

  @override
  int get hashCode => Object.hash(id, type);

  @override
  String toString() => 'NodeRef($id/$type)';
}

/// 画布行为种类。
enum CanvasActionKind {
  create,
  update,
  move,
  resize,
  remove,
  group,
  ungroup,
  edge,
  removeEdge;

  static CanvasActionKind fromString(String raw) {
    return CanvasActionKind.values.firstWhere(
      (k) => k.name == raw,
      orElse: () => throw ArgumentError('Unknown CanvasActionKind: $raw'),
    );
  }
}

/// 一条画布行为记录（append-only 的最小单元）。
class CanvasActionEntry {
  final DateTime occurredAt;
  final CanvasActionKind kind;
  final NodeRef nodeRef;

  /// 行为是否成功。失败请求照常追加（可审计），但不计入阈值。
  final bool succeeded;

  const CanvasActionEntry({
    required this.occurredAt,
    required this.kind,
    required this.nodeRef,
    this.succeeded = true,
  });

  factory CanvasActionEntry.fromJson(Map<String, dynamic> json) {
    return CanvasActionEntry(
      occurredAt: DateTime.parse(json['occurred_at'] as String),
      kind: CanvasActionKind.fromString(json['kind'] as String),
      nodeRef: NodeRef.fromJson(json['node_ref'] as Map<String, dynamic>),
      succeeded: (json['succeeded'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'kind': kind.name,
        'node_ref': nodeRef.toJson(),
        'succeeded': succeeded,
      };
}

/// 行为流的消费端（记忆策展器接口占位）。
///
/// 达阈值时由日志把一批行为交给 consumer；Phase 3 在此接入压缩分析。
abstract interface class CanvasActionConsumer {
  Future<void> consume(List<CanvasActionEntry> batch);
}

/// append-only 画布行为日志接口。
abstract interface class CanvasActionLog {
  /// 追加一条行为。已写入的条目永不可修改或删除。
  Future<void> append(CanvasActionEntry entry);

  /// 全部已记录行为（按时间先后）。
  List<CanvasActionEntry> get entries;

  /// 距离下次触发分析的成功行为计数。
  int get pendingCount;
}

/// 带阈值触发的内存实现。
///
/// - 只追加，不修改既有条目；
/// - 失败请求（[CanvasActionEntry.succeeded] == false）不计入 [pendingCount]；
/// - 成功计数达到 [threshold] 时调用 [consumer] 消费整批一次，然后清零。
class ThresholdCanvasActionLog implements CanvasActionLog {
  final CanvasActionConsumer consumer;
  final int threshold;

  final List<CanvasActionEntry> _entries = [];
  int _pendingCount = 0;
  int _triggerCount = 0;

  ThresholdCanvasActionLog({
    required this.consumer,
    this.threshold = 50,
  }) : assert(threshold > 0, 'threshold must be positive');

  @override
  Future<void> append(CanvasActionEntry entry) async {
    _entries.add(entry);
    if (!entry.succeeded) return;

    _pendingCount++;
    if (_pendingCount >= threshold) {
      final batch = List<CanvasActionEntry>.unmodifiable(
        _entries.where((e) => e.succeeded),
      );
      // 先清零再消费：消费端失败也不会反复触发同一批。
      _pendingCount = 0;
      _triggerCount++;
      await consumer.consume(batch);
    }
  }

  @override
  List<CanvasActionEntry> get entries =>
      List.unmodifiable(_entries.toList(growable: false));

  @override
  int get pendingCount => _pendingCount;

  /// 已触发的分析次数（供测试与观察）。
  int get triggerCount => _triggerCount;
}
