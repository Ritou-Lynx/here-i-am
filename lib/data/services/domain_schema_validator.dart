import 'dart:convert';

import 'package:memex/domain/models/domain_schemas.dart';
import 'package:memex/utils/logger.dart';

/// Result from [DomainSchemaValidator.validate].
class ValidationResult {
  const ValidationResult({
    required this.normalizedPatch,
    required this.needsReview,
    required this.warnings,
  });

  /// The patch with field names normalized and off-schema fields moved to extras.
  final Map<String, dynamic> normalizedPatch;

  /// True if the patch had issues that need human review.
  final bool needsReview;

  final List<String> warnings;
}

/// Validates and normalizes a patch against a [DomainSchema].
///
/// Rules:
/// - Reserved `_*` fields are passed through unchanged and are never moved to extras.
/// - Fields in the schema are type-coerced where possible (number strings → num,
///   datetime strings → ISO 8601).
/// - Unrecognized fields are moved into `extras` (not discarded).
/// - Enum fields with out-of-vocabulary values are flagged with needsReview.
/// - Amount fields with trailing units ("元", "块", etc.) are stripped.
class DomainSchemaValidator {
  const DomainSchemaValidator();

  static final _logger = getLogger('DomainSchemaValidator');

  /// Validate and normalize [patch] for the given [domain].
  /// Returns the normalized patch ready for insertion.
  ValidationResult validate(String domain, Map<String, dynamic> patch) {
    final schema = allDomainSchemas[domain];
    if (schema == null) {
      // Unknown domain — pass through as-is, flag for review
      return ValidationResult(
        normalizedPatch: Map<String, dynamic>.from(patch),
        needsReview: true,
        warnings: ['Unknown domain: $domain'],
      );
    }

    final normalized = <String, dynamic>{};
    final extras = <String, dynamic>{};
    final warnings = <String>[];
    var needsReview = false;

    for (final entry in patch.entries) {
      final key = entry.key;
      final value = entry.value;

      // Reserved fields pass through unchanged
      if (key.startsWith('_')) {
        normalized[key] = value;
        continue;
      }

      final fieldDef = schema.fields
          .where((f) => f.name == key)
          .firstOrNull;

      if (fieldDef == null) {
        // Off-schema field — move to extras
        extras[key] = value;
        continue;
      }

      final coerced = _coerce(fieldDef, value, warnings);
      if (coerced is _ValidationError) {
        warnings.add('Field "$key": ${coerced.message}');
        needsReview = true;
        extras[key] = value; // keep original in extras
      } else {
        normalized[key] = coerced;
      }

      // Check enum vocabulary
      if (fieldDef.type == DomainFieldType.enumType &&
          coerced is String &&
          !(fieldDef.enumValues?.contains(coerced) ?? true)) {
        warnings.add(
            'Field "$key": "$coerced" not in allowed values ${fieldDef.enumValues}');
        needsReview = true;
      }
    }

    if (extras.isNotEmpty) {
      normalized['extras'] = {
        ...(normalized['extras'] as Map<String, dynamic>? ?? {}),
        ...extras,
      };
    }

    if (needsReview) {
      normalized['needs_review'] = true;
    }

    if (warnings.isNotEmpty) {
      _logger.warning('DomainSchemaValidator [$domain]: ${warnings.join('; ')}');
    }

    return ValidationResult(
      normalizedPatch: normalized,
      needsReview: needsReview,
      warnings: warnings,
    );
  }

  dynamic _coerce(
      DomainFieldDef field, dynamic value, List<String> warnings) {
    if (value == null) return null;
    switch (field.type) {
      case DomainFieldType.number:
        if (value is num) return value;
        if (value is String) {
          final cleaned = _stripCurrencyUnits(value);
          final parsed = num.tryParse(cleaned);
          if (parsed != null) return parsed;
          return _ValidationError('cannot parse "$value" as number');
        }
        return _ValidationError('expected number, got ${value.runtimeType}');

      case DomainFieldType.string:
      case DomainFieldType.enumType:
        return value.toString();

      case DomainFieldType.datetime:
        if (value is String) {
          final dt = DateTime.tryParse(value);
          if (dt != null) return dt.toIso8601String();
          return _ValidationError('cannot parse "$value" as datetime');
        }
        if (value is int) {
          // Assume microseconds since epoch
          return DateTime.fromMicrosecondsSinceEpoch(value).toIso8601String();
        }
        return _ValidationError('expected datetime string, got ${value.runtimeType}');

      case DomainFieldType.boolean:
        if (value is bool) return value;
        if (value is String) {
          if (value == 'true') return true;
          if (value == 'false') return false;
          return _ValidationError('cannot parse "$value" as boolean');
        }
        return _ValidationError('expected boolean, got ${value.runtimeType}');
    }
  }

  static String _stripCurrencyUnits(String s) {
    return s
        .replaceAll(RegExp(r'[元块圆￥\$€£]'), '')
        .replaceAll(',', '')
        .trim();
  }

  /// Convenience: validate and encode [patch] to JSON string.
  String validateAndEncode(String domain, Map<String, dynamic> patch) {
    final result = validate(domain, patch);
    return jsonEncode(result.normalizedPatch);
  }
}

class _ValidationError {
  const _ValidationError(this.message);
  final String message;
}
