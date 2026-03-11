import 'package:flutter/material.dart';

/// Helper class for getting icons from string names
class IconHelper {
  static Widget getIcon(String iconName, {double size = 24, Color? color}) {
    final iconData = _getIconData(iconName);
    final iconColor = color ?? Colors.black;
    
    if (iconData != null) {
      return Icon(iconData, size: size, color: iconColor);
    }
    
    // Fallback: return emoji or text if icon not found
    return Text(
      _getEmoji(iconName),
      style: TextStyle(fontSize: size, color: iconColor),
    );
  }

  static IconData? _getIconData(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'smile':
        return Icons.sentiment_satisfied;
      case 'wallet':
        return Icons.account_balance_wallet;
      case 'plane':
        return Icons.flight;
      case 'heart':
        return Icons.favorite;
      case 'activity':
        return Icons.monitor_heart;
      case 'sun':
        return Icons.wb_sunny;
      case 'dollar-sign':
        return Icons.attach_money;
      case 'briefcase':
        return Icons.business_center;
      default:
        return null;
    }
  }

  static String _getEmoji(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'smile':
        return '😊';
      case 'wallet':
        return '💳';
      case 'plane':
        return '✈️';
      case 'heart':
        return '❤️';
      case 'activity':
        return '💓';
      case 'sun':
        return '☀️';
      case 'dollar-sign':
        return '💰';
      case 'briefcase':
        return '💼';
      default:
        return '📊';
    }
  }
}

