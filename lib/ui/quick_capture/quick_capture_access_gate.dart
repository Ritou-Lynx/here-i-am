import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../../data/personal_data_hub/quick_capture_models.dart';

/// Engine-local permission to mount capture UI. Every Flutter engine starts
/// denied. Only the app authentication/lifecycle owner may grant access after
/// completing its checks; a launch intent never grants it.
abstract final class QuickCaptureAccess {
  static final ValueNotifier<bool> instance = ValueNotifier<bool>(false);
}

/// The builder is deliberately lazy: the locked state does not construct a
/// capture page, view model, microphone adapter, or any other child dependency.
/// Revoking access removes the subtree so its normal disposal stops recording.
class QuickCaptureAccessGate extends StatefulWidget {
  const QuickCaptureAccessGate({super.key, required this.builder, this.access});

  final WidgetBuilder builder;
  final ValueListenable<bool>? access;

  @override
  State<QuickCaptureAccessGate> createState() => _QuickCaptureAccessGateState();
}

/// Only the unsent text and its stable ID survive a temporary lock. This is
/// route-local memory: no microphone, view model, or persistence is retained.
class QuickCaptureDraftSession {
  QuickCaptureDraft? draft;

  static QuickCaptureDraftSession? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_QuickCaptureDraftScope>()?.session;
}

class _QuickCaptureAccessGateState extends State<QuickCaptureAccessGate> {
  final _session = QuickCaptureDraftSession();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: widget.access ?? QuickCaptureAccess.instance,
        builder: (context, allowed, _) => allowed
            ? _QuickCaptureDraftScope(
                session: _session, child: Builder(builder: widget.builder))
            : const SizedBox.shrink(),
      );
}

class _QuickCaptureDraftScope extends InheritedWidget {
  const _QuickCaptureDraftScope({required this.session, required super.child});
  final QuickCaptureDraftSession session;

  @override
  bool updateShouldNotify(_QuickCaptureDraftScope oldWidget) => false;
}
