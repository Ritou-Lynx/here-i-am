library;

import 'package:memex/domain/workbench_ai/runtime/runtime_session_binding.dart';

/// The recovery boundary a binding store can honestly guarantee.
enum WorkbenchBindingDurability {
  /// Bindings disappear with the Flutter process.
  processMemory,

  /// Bindings can be loaded after the application process restarts.
  applicationRestart,
}

/// Product-owned storage boundary for provider-neutral runtime bindings.
///
/// A store persists only [RuntimeSessionBinding]. Local runtime session ids and
/// active turn ids remain transport state and must never be restored after a
/// Bridge or application restart. A durable implementation therefore resumes
/// the opaque provider session and creates a fresh local runtime session.
abstract interface class WorkbenchRuntimeBindingStore {
  WorkbenchBindingDurability get durability;

  Future<RuntimeSessionBinding?> read(String conversationId);

  Future<void> write(RuntimeSessionBinding binding);
}

/// Explicitly volatile store used until W0 approves a durable product schema.
class InMemoryWorkbenchRuntimeBindingStore
    implements WorkbenchRuntimeBindingStore {
  final Map<String, RuntimeSessionBinding> _bindings = {};

  @override
  WorkbenchBindingDurability get durability =>
      WorkbenchBindingDurability.processMemory;

  @override
  Future<RuntimeSessionBinding?> read(String conversationId) async =>
      _bindings[conversationId];

  @override
  Future<void> write(RuntimeSessionBinding binding) async {
    _bindings[binding.conversationId] = binding;
  }
}
