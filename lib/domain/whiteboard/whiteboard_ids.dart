/// Stable string IDs for all cross-device whiteboard entities.
///
/// All whiteboard entities use globally stable string IDs; local integer IDs
/// are only used as cache indices. This module provides a guarded factory and
/// validation helpers so that no entity accidentally uses a non-string or
/// empty identity.
library;

import 'dart:math';

final _random = Random();

/// A stable, non-empty string identifier.
///
/// Wraps a plain [String] to make intent explicit at type level and to enforce
/// the "never empty, never null" invariant in a single place.
class StableId {
  final String value;

  const StableId._(this.value);

  /// Generates a new random stable ID with an optional [prefix].
  ///
  /// Example: `StableId.generate('card')` → `card_a1b2c3d4e5f6g7h8`.
  factory StableId.generate([String? prefix]) {
    final hex = List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join();
    return StableId._(prefix == null || prefix.isEmpty ? hex : '${prefix}_$hex');
  }

  /// Creates a [StableId] from an existing string.
  ///
  /// Throws [ArgumentError] if [value] is empty or not a string-like type.
  factory StableId(Object? value) {
    if (value is! String || value.isEmpty) {
      throw ArgumentError('StableId must be a non-empty string, got: $value');
    }
    return StableId._(value);
  }

  /// Returns `true` if [other] is a [StableId] with the same [value].
  @override
  bool operator ==(Object other) =>
      other is StableId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Validates that a value is a non-empty string suitable as a stable ID.
///
/// Returns the string if valid, otherwise `null`.
String? tryStableId(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}