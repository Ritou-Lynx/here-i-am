import 'package:flutter/material.dart';

/// Centralized shadow definitions.
class AppShadows {
  const AppShadows._();

  /// Standard card shadow: subtle elevation
  static const BoxShadow card = BoxShadow(
    color: Color(0x0D293025), // 5% warm ink
    blurRadius: 16,
    offset: Offset(0, 2),
  );

  /// Snapshot/event card shadow
  static const BoxShadow cardAccent = BoxShadow(
    color: Color(0x0D293025), // warm ink
    blurRadius: 24,
  );

  /// Event card shadow
  static const BoxShadow eventCard = BoxShadow(
    color: Color(0x08293025), // warm ink
    blurRadius: 18,
  );

  /// Back button shadow
  static const BoxShadow backButton = BoxShadow(
    color: Color(0x0A293025), // 4% warm ink
    blurRadius: 9,
  );

  /// Floating element shadow
  static const BoxShadow floating = BoxShadow(
    color: Color(0x14293025), // 8% warm ink
    blurRadius: 24,
    offset: Offset(0, 6),
  );
}
