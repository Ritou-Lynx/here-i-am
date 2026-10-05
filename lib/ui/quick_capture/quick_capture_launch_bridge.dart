import 'package:flutter/services.dart';

/// Install before normal shell navigation; cold launch is also available as
/// the native initial route /quick-capture. Host deduplicates that initial page.
class QuickCaptureLaunchBridge {
  QuickCaptureLaunchBridge({MethodChannel? channel})
      : channel =
            channel ?? const MethodChannel('com.memexlab.memex/quick_capture');
  final MethodChannel channel;
  final Set<String> _seen = {};
  Future<void> start(void Function() open) async {
    void receive(dynamic action) {
      if (action is String && _seen.add(action)) open();
    }

    channel.setMethodCallHandler((call) async {
      if (call.method == 'capture') receive(call.arguments);
    });
    receive(await channel.invokeMethod<String>('takePendingCapture'));
  }

  Future<void> close() => channel.invokeMethod<void>('finishCapture');
  void dispose() => channel.setMethodCallHandler(null);
}
