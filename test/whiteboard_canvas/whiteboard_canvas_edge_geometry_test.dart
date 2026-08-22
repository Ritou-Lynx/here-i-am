import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/ui/whiteboard_canvas/edge_geometry.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';

void main() {
  final now = DateTime.utc(2026, 8, 22);

  BoardItem item(
    String id, {
    required double x,
    required double y,
    double width = 160,
    double height = 120,
  }) =>
      BoardItem(
        itemId: id,
        boardId: 'board',
        cardId: 'card_$id',
        x: x,
        y: y,
        width: width,
        height: height,
      );

  BoardEdge edge({Map<String, dynamic> style = const {}}) => BoardEdge(
        edgeId: 'edge',
        boardId: 'board',
        fromItemId: 'from',
        toItemId: 'to',
        style: style,
        createdAt: now,
      );

  test('persisted four-way sides resolve against current BoardItem bounds', () {
    final connection = CanvasEdgeGeometry.resolve(
      edge: edge(style: const {
        CanvasEdgeGeometry.fromAnchorStyleKey: 'right',
        CanvasEdgeGeometry.toAnchorStyleKey: 'left',
      }),
      from: item('from', x: 10, y: 20),
      to: item('to', x: 400, y: 60, width: 220, height: 180),
    );

    expect(connection.from.dx, 170);
    expect(connection.from.dy, 80);
    expect(connection.to.dx, 400);
    expect(connection.to.dy, 150);
    expect(connection.fromSide, CanvasAnchorSide.right);
    expect(connection.toSide, CanvasAnchorSide.left);
  });

  test('moving and resizing items recomputes endpoints without stale pixels',
      () {
    final anchored = edge(style: const {
      CanvasEdgeGeometry.fromAnchorStyleKey: 'bottom',
      CanvasEdgeGeometry.toAnchorStyleKey: 'top',
    });
    final before = CanvasEdgeGeometry.resolve(
      edge: anchored,
      from: item('from', x: 0, y: 0),
      to: item('to', x: 100, y: 300),
    );
    final after = CanvasEdgeGeometry.resolve(
      edge: anchored,
      from: item('from', x: 50, y: 40, width: 300, height: 200),
      to: item('to', x: 220, y: 460, width: 240, height: 100),
    );

    expect(before.from.dx, 80);
    expect(before.from.dy, 120);
    expect(after.from.dx, 200);
    expect(after.from.dy, 240);
    expect(after.to.dx, 340);
    expect(after.to.dy, 460);
  });

  test('legacy edges derive stable boundary sides instead of using centers',
      () {
    final connection = CanvasEdgeGeometry.resolve(
      edge: edge(),
      from: item('from', x: 0, y: 0),
      to: item('to', x: 400, y: 10),
    );

    expect(connection.fromSide, CanvasAnchorSide.right);
    expect(connection.toSide, CanvasAnchorSide.left);
    expect(connection.from.dx, 160);
    expect(connection.to.dx, 400);
  });

  test('anchor sides survive move resize undo redo and JSON restart', () {
    final snapshot = WhiteboardSnapshot(
      boards: [Board(boardId: 'board', name: 'B', createdAt: now)],
      cards: [
        CardContract(
          cardId: 'card_from',
          cardKind: CardKind.note,
          title: 'From',
          createdAt: now,
        ),
        CardContract(
          cardId: 'card_to',
          cardKind: CardKind.note,
          title: 'To',
          createdAt: now,
        ),
      ],
      boardItems: [
        item('from', x: 0, y: 0),
        item('to', x: 400, y: 0),
      ],
    );
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: snapshot,
      boardId: 'board',
    );
    expect(
      vm.createEdge(
        fromItemId: 'from',
        toItemId: 'to',
        style: const {
          CanvasEdgeGeometry.fromAnchorStyleKey: 'right',
          CanvasEdgeGeometry.toAnchorStyleKey: 'left',
        },
      ),
      isTrue,
    );
    vm.selectItem('from');
    vm.moveSelectedItems(80, 40);
    vm.resizeItem(itemId: 'from', width: 300, height: 200);

    CanvasEdgeConnection current() {
      final saved = vm.exportForSave();
      return CanvasEdgeGeometry.resolve(
        edge: saved.edges.single,
        from: saved.boardItems.firstWhere((value) => value.itemId == 'from'),
        to: saved.boardItems.firstWhere((value) => value.itemId == 'to'),
      );
    }

    expect(current().from, const Offset(380, 140));
    vm.undo();
    expect(current().from, const Offset(240, 100));
    vm.undo();
    expect(current().from, const Offset(160, 60));
    vm.redo();
    vm.redo();
    expect(current().from, const Offset(380, 140));

    final restarted = WhiteboardCanvasViewModel(
      initialSnapshot: WhiteboardSnapshot.fromJson(vm.exportForSave().toJson()),
      boardId: 'board',
    );
    final restored = restarted.exportForSave();
    expect(restored.edges.single.style, const {
      CanvasEdgeGeometry.fromAnchorStyleKey: 'right',
      CanvasEdgeGeometry.toAnchorStyleKey: 'left',
    });
    expect(
      CanvasEdgeGeometry.resolve(
        edge: restored.edges.single,
        from: restored.boardItems.firstWhere((value) => value.itemId == 'from'),
        to: restored.boardItems.firstWhere((value) => value.itemId == 'to'),
      ).from,
      const Offset(380, 140),
    );
  });
}
