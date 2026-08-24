/// Serializes disposal and subsequent initialization of Windows WebView2
/// controllers used by video providers.
library;

class WindowsWebViewLifecycle {
  WindowsWebViewLifecycle._();

  static Future<void> _previousDisposal = Future<void>.value();

  static Future<void> waitForPreviousDisposal() => _previousDisposal;

  static void registerDisposal(Future<void> disposal) {
    _previousDisposal = disposal.then<void>((_) {}, onError: (_) {});
  }
}
