/// Semantic-zoom LOD tiers for canvas cards.
///
/// Huabu-style LOD (`docs/development/WHITEBOARD_EXTERNAL_REFERENCE_HUABU.md`
/// §5): a card's *screen* width (`cardWidth × zoom`) decides between
/// `full` and `minimal` rendering, with hysteresis to prevent flickering at
/// the boundary. Pure logic — no Flutter dependency, unit-testable.
library;

/// Rendering fidelity tier for a canvas card.
enum LodTier {
  /// Full preview: title + body + tags (the default).
  full,

  /// Compact preview: title only, reduced padding.
  minimal,
}

/// LOD thresholds in screen pixels.
abstract final class LodThresholds {
  /// A `full` card collapses to `minimal` below this screen width.
  static const double fullToMinimal = 140.0;

  /// A `minimal` card expands back to `full` above this screen width.
  ///
  /// The 10px gap between [fullToMinimal] and [minimalToFull] is the
  /// hysteresis band that prevents toggling on small zoom jitters.
  static const double minimalToFull = 150.0;
}

/// Returns the tier to render next for a card currently at [current] whose
/// on-screen width is [screenWidth] (canvas width × zoom).
LodTier nextLodTier({
  required LodTier current,
  required double screenWidth,
}) {
  switch (current) {
    case LodTier.full:
      return screenWidth < LodThresholds.fullToMinimal
          ? LodTier.minimal
          : LodTier.full;
    case LodTier.minimal:
      return screenWidth > LodThresholds.minimalToFull
          ? LodTier.full
          : LodTier.minimal;
  }
}
