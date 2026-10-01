/// Process-broker lease required before a diagnostic outbox opens its file gate.
/// Implementations keep the broker credential opaque and never expose it to UI.
abstract interface class ActivityOutboxProcessLease {
  String get source;
  bool get isHeld;
  bool get hasFileClaim;

  void claimFileAccess(Object claimant, String source);
  void verifyFileAccess(Object claimant, String source);
  void releaseFileAccess(Object claimant);
}
