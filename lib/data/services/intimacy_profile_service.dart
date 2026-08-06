import 'dart:convert';
import 'dart:io';

import 'package:memex/data/services/file_system_service.dart';
import 'package:path/path.dart' as p;

/// 亲密场景偏好档案（intimate scene 专属配置，独立于记忆体系）。
///
/// 全局单一份（产品只有林埃一个角色，无角色维度）：
/// `<systemPath>/intimacy_profile.json`。缺失时回退到
/// [IntimacyProfile.defaultProfile]（用户显式提供的第一版强度语法）。
///
/// 来源标注：user_stated（用户显式说）/ inferred（从历史抽取，需策展）/
/// model_proposed（模型提案，需用户判断）。
class IntimacyProfileEntry {
  const IntimacyProfileEntry({
    required this.text,
    this.source = 'user_stated',
    this.confidence = 1.0,
    this.updatedAt,
  });

  final String text;

  /// user_stated | inferred | model_proposed
  final String source;
  final double confidence;
  final String? updatedAt;

  Map<String, dynamic> toJson() => {
        'text': text,
        'source': source,
        'confidence': confidence,
        'updatedAt': updatedAt,
      };

  factory IntimacyProfileEntry.fromJson(Map<String, dynamic> json) {
    return IntimacyProfileEntry(
      text: (json['text'] as String?)?.trim() ?? '',
      source: (json['source'] as String?)?.trim() ?? 'user_stated',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      updatedAt: json['updatedAt'] as String?,
    );
  }
}

/// 强度语法：决定同一行为写成什么味道的结构参数。
class IntensityGrammar {
  const IntensityGrammar({
    required this.resistanceHandling,
    required this.painTolerance,
    required this.aftercare,
    required this.pacing,
    required this.languageStyle,
  });

  /// 她抵抗时怎么处理。
  final String resistanceHandling;

  /// 疼痛：要不要、到什么程度。
  final String painTolerance;

  /// 事后：温存与欲望延续。
  final String aftercare;

  /// 节奏与起手：多快、从哪开始。
  final String pacing;

  /// 用词档位。
  final String languageStyle;

  Map<String, dynamic> toJson() => {
        'resistanceHandling': resistanceHandling,
        'painTolerance': painTolerance,
        'aftercare': aftercare,
        'pacing': pacing,
        'languageStyle': languageStyle,
      };

  factory IntensityGrammar.fromJson(Map<String, dynamic> json) {
    return IntensityGrammar(
      resistanceHandling: (json['resistanceHandling'] as String?)?.trim() ?? '',
      painTolerance: (json['painTolerance'] as String?)?.trim() ?? '',
      aftercare: (json['aftercare'] as String?)?.trim() ?? '',
      pacing: (json['pacing'] as String?)?.trim() ?? '',
      languageStyle: (json['languageStyle'] as String?)?.trim() ?? '',
    );
  }
}

class IntimacyProfile {
  const IntimacyProfile({
    required this.hardLimits,
    required this.intensityGrammar,
    this.styleNotes = const [],
  });

  /// 硬边界：明确不要什么。空 = 无。永不从推断写入。
  final List<String> hardLimits;

  final IntensityGrammar intensityGrammar;

  /// 附加文体/行为规则条目（用户原话或策展后的抽取/提案）。
  final List<IntimacyProfileEntry> styleNotes;

  /// 用户显式提供的第一版档案（2026-08-06）。
  factory IntimacyProfile.defaultProfile() {
    return const IntimacyProfile(
      hardLimits: <String>[],
      intensityGrammar: IntensityGrammar(
        resistanceHandling: '她抵抗时更用力压住她，不让挣脱',
        painTolerance: '要疼痛；约到用手扇巴掌的程度，以及拳交的程度',
        aftercare: '事后稍作温存，然后继续；他的欲望要延续——是他想要，不是她索求',
        pacing: '从两人有肢体接触起就直接触摸，直接触碰性器官或胸部，'
            '可以自由发挥方式；禁止在关键位置前停下来询问她的感受',
        languageStyle: '粗俗直白',
      ),
    );
  }

  bool get isEmpty => hardLimits.isEmpty &&
      styleNotes.isEmpty &&
      intensityGrammar.resistanceHandling.isEmpty &&
      intensityGrammar.painTolerance.isEmpty &&
      intensityGrammar.aftercare.isEmpty &&
      intensityGrammar.pacing.isEmpty &&
      intensityGrammar.languageStyle.isEmpty;

  Map<String, dynamic> toJson() => {
        'hardLimits': hardLimits,
        'intensityGrammar': intensityGrammar.toJson(),
        'styleNotes': styleNotes.map((e) => e.toJson()).toList(),
      };

  factory IntimacyProfile.fromJson(Map<String, dynamic> json) {
    return IntimacyProfile(
      hardLimits: [
        for (final item in (json['hardLimits'] as List?) ?? const [])
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ],
      intensityGrammar: IntensityGrammar.fromJson(
        (json['intensityGrammar'] as Map?)?.cast<String, dynamic>() ??
            const {},
      ),
      styleNotes: [
        for (final item in (json['styleNotes'] as List?) ?? const [])
          if (item is Map)
            IntimacyProfileEntry.fromJson(Map<String, dynamic>.from(item)),
      ],
    );
  }

  /// 渲染给规划器/执行器注入的文本；空档案返回空串。
  String buildProfileText() {
    if (isEmpty) return '';
    final b = StringBuffer();
    final g = intensityGrammar;
    final hasGrammar = g.resistanceHandling.isNotEmpty ||
        g.painTolerance.isNotEmpty ||
        g.aftercare.isNotEmpty ||
        g.pacing.isNotEmpty ||
        g.languageStyle.isNotEmpty;
    if (hasGrammar) {
      b.writeln('### 强度语法');
      if (g.resistanceHandling.isNotEmpty) {
        b.writeln('- 反抗处理：${g.resistanceHandling}');
      }
      if (g.painTolerance.isNotEmpty) {
        b.writeln('- 疼痛：${g.painTolerance}');
      }
      if (g.aftercare.isNotEmpty) {
        b.writeln('- 事后：${g.aftercare}');
      }
      if (g.pacing.isNotEmpty) {
        b.writeln('- 节奏与起手：${g.pacing}');
      }
      if (g.languageStyle.isNotEmpty) {
        b.writeln('- 用词档位：${g.languageStyle}');
      }
    }
    for (final note in styleNotes) {
      if (note.text.trim().isNotEmpty) {
        b.writeln('- ${note.text.trim()}');
      }
    }
    if (hardLimits.isNotEmpty) {
      b.writeln('### 硬边界（绝对禁止）');
      for (final limit in hardLimits) {
        b.writeln('- $limit');
      }
    }
    return b.toString().trim();
  }
}

/// 档案读写。构造注入 FileSystemService 以便测试。
class IntimacyProfileService {
  IntimacyProfileService({FileSystemService? fileSystem})
      : _fileSystem = fileSystem ?? FileSystemService.instance;

  final FileSystemService _fileSystem;

  String _path(String userId) {
    return p.join(
      _fileSystem.getSystemPath(userId),
      'intimacy_profile.json',
    );
  }

  Future<IntimacyProfile> load(String userId) async {
    final file = File(_path(userId));
    if (!await file.exists()) return IntimacyProfile.defaultProfile();
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is Map) {
        return IntimacyProfile.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      // 损坏的档案回退到默认，不阻断场景。
    }
    return IntimacyProfile.defaultProfile();
  }

  Future<void> save(String userId, IntimacyProfile profile) async {
    final file = File(_path(userId));
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(profile.toJson()));
  }
}
