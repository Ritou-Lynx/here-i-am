/// Whiteboard domain contracts — the shared contract surface for W0.
///
/// This library exports all shared whiteboard contract types. It has zero
/// dependencies on MemexRouter, CardCache, Drift, or any UI code. It can be
/// copied to a standalone Flutter project and still compile.
///
/// See:
/// - `docs/design/whiteboard-ui-spine-contract.md` for the product/data spine
/// - `docs/development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md` for the
///   workstream charter and change discipline
/// - `docs/development/WHITEBOARD_ENGINE_ADAPTER_ADR.md` for the engine
///   adapter boundary decision

library whiteboard_contracts;

export 'whiteboard_ids.dart';
export 'source_content.dart';
export 'card_contract.dart';
export 'board.dart';
export 'anchor_contract.dart';
export 'whiteboard_snapshot.dart';
export 'ingestion_result.dart';
export 'rich_text_document.dart';
export 'player_adapter.dart';