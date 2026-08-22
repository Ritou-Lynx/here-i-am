/// Narrow canvas ↔ Card editor embedding boundary.
///
/// The canvas owns placement, gestures, and whether a Card is editing. The
/// injected surface owns only Card content editing. This keeps the canvas from
/// depending on rich-text controller internals while allowing Wave 3 A to
/// replace the surface without touching canvas gesture code.
library;

import 'package:flutter/widgets.dart';

import 'package:memex/domain/whiteboard/card_contract.dart';

typedef BoardItemEditSurfaceBuilder = Widget Function(
  BuildContext context,
  BoardItemEditRequest request,
);

class BoardItemEditRequest {
  const BoardItemEditRequest({
    required this.cardId,
    required this.isReadonly,
    required this.onSaved,
    required this.onClose,
    required this.onExpand,
  });

  final String cardId;
  final bool isReadonly;
  final ValueChanged<CardContract> onSaved;
  final VoidCallback onClose;
  final ValueChanged<CardContract> onExpand;
}
