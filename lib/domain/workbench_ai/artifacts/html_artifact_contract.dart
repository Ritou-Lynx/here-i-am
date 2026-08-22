library;

import '../../whiteboard/whiteboard_ids.dart';

enum HtmlRuntimeCapability {
  inlineStyles,
  images,
  scripts,
  canvas,
  network,
  forms,
  clipboardWrite,
  navigation,
  downloads,
  popups,
  fileAccess,
  localhostAccess,
  broadBridge;

  static HtmlRuntimeCapability fromWire(String value) => values.firstWhere(
        (candidate) => candidate.wireName == value,
        orElse: () => throw ArgumentError('Unknown HTML capability: $value'),
      );

  String get wireName => switch (this) {
        inlineStyles => 'inline_styles',
        clipboardWrite => 'clipboard_write',
        fileAccess => 'file_access',
        localhostAccess => 'localhost_access',
        broadBridge => 'broad_bridge',
        _ => name,
      };
}

enum HtmlAuditStatus {
  pending,
  accepted,
  rejected;

  static HtmlAuditStatus fromWire(String value) => values.firstWhere(
        (candidate) => candidate.name == value,
        orElse: () => throw ArgumentError('Unknown HTML audit status: $value'),
      );
}

/// Capabilities granted to a reviewed runtime bundle.
///
/// This is not a sanitizer. A later packager must turn raw authored HTML into
/// an immutable runtime bundle and prove it conforms to this policy.
class HtmlSandboxPolicy {
  const HtmlSandboxPolicy({
    required this.policyVersion,
    required this.csp,
    this.capabilities = const {},
    this.allowedNetworkOrigins = const [],
    this.allowedBridgeMethods = const [],
    this.scriptHashes = const [],
  });

  final int policyVersion;
  final String csp;
  final Set<HtmlRuntimeCapability> capabilities;
  final List<String> allowedNetworkOrigins;
  final List<String> allowedBridgeMethods;
  final List<String> scriptHashes;

  factory HtmlSandboxPolicy.fromJson(
    Map<String, dynamic> json,
  ) =>
      HtmlSandboxPolicy(
        policyVersion: (json['policy_version'] as num).toInt(),
        csp: json['csp'] as String,
        capabilities: (json['capabilities'] as List<dynamic>? ?? const [])
            .cast<String>()
            .map(HtmlRuntimeCapability.fromWire)
            .toSet(),
        allowedNetworkOrigins:
            (json['allowed_network_origins'] as List<dynamic>? ?? const [])
                .cast(),
        allowedBridgeMethods:
            (json['allowed_bridge_methods'] as List<dynamic>? ?? const [])
                .cast(),
        scriptHashes:
            (json['script_hashes'] as List<dynamic>? ?? const []).cast(),
      );

  Map<String, dynamic> toJson() => {
        'policy_version': policyVersion,
        'csp': csp,
        'capabilities': capabilities.map((value) => value.wireName).toList()
          ..sort(),
        if (allowedNetworkOrigins.isNotEmpty)
          'allowed_network_origins': allowedNetworkOrigins,
        if (allowedBridgeMethods.isNotEmpty)
          'allowed_bridge_methods': allowedBridgeMethods,
        if (scriptHashes.isNotEmpty) 'script_hashes': scriptHashes,
      };
}

/// Binds immutable authored HTML to a separately reviewed runtime bundle.
class HtmlRuntimeBundle {
  const HtmlRuntimeBundle({
    required this.rawArtifactId,
    required this.runtimeArtifactId,
    required this.runtimeObjectRef,
    required this.runtimeSha256,
    required this.auditStatus,
    required this.policy,
    this.auditFindings = const [],
  });

  final String rawArtifactId;
  final String runtimeArtifactId;
  final String runtimeObjectRef;
  final String runtimeSha256;
  final HtmlAuditStatus auditStatus;
  final HtmlSandboxPolicy policy;
  final List<String> auditFindings;

  factory HtmlRuntimeBundle.fromJson(Map<String, dynamic> json) =>
      HtmlRuntimeBundle(
        rawArtifactId: StableId(json['raw_artifact_id']).value,
        runtimeArtifactId: StableId(json['runtime_artifact_id']).value,
        runtimeObjectRef: json['runtime_object_ref'] as String,
        runtimeSha256: json['runtime_sha256'] as String,
        auditStatus: HtmlAuditStatus.fromWire(json['audit_status'] as String),
        policy: HtmlSandboxPolicy.fromJson(
          Map<String, dynamic>.from(json['policy'] as Map),
        ),
        auditFindings:
            (json['audit_findings'] as List<dynamic>? ?? const []).cast(),
      );

  Map<String, dynamic> toJson() => {
        'raw_artifact_id': rawArtifactId,
        'runtime_artifact_id': runtimeArtifactId,
        'runtime_object_ref': runtimeObjectRef,
        'runtime_sha256': runtimeSha256,
        'audit_status': auditStatus.name,
        'policy': policy.toJson(),
        if (auditFindings.isNotEmpty) 'audit_findings': auditFindings,
      };
}
