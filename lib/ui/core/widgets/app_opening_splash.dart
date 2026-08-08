import 'package:flutter/material.dart';

/// Spring Rain Daydream opening animation used while the app is bootstrapping.
class AppOpeningSplash extends StatelessWidget {
  const AppOpeningSplash({super.key, this.statusText});

  static const assetPath = 'assets/images/spring_rain_daydream_splash_v5.webp';
  static const backgroundColor = Color(0xFFF3F3EC);

  final String? statusText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            assetPath,
            key: const ValueKey('app_opening_animation'),
            fit: BoxFit.contain,
            alignment: Alignment.center,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            excludeFromSemantics: true,
          ),
          if (statusText case final text?)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6E704E),
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
