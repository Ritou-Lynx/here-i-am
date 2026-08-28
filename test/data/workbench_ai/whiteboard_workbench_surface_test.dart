import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/workbench_ai/whiteboard_workbench_surface.dart';

void main() {
  test('only the attached route owner can update or detach the surface', () {
    final controller = WhiteboardWorkbenchSurfaceController.instance;
    final owner = Object();
    final stranger = Object();
    final previousOwner = controller.current?.owner;
    if (previousOwner != null) controller.detach(previousOwner);

    controller.attach(
      owner: owner,
      boardId: 'board_1',
      selectedItemIds: {'item_1'},
      flush: () async => true,
      reload: () async => true,
    );
    controller.updateSelection(stranger, {'item_2'});
    expect(controller.current!.selectedItemIds, {'item_1'});

    controller.updateSelection(owner, {'item_1', 'item_2'});
    expect(controller.current!.selectedItemIds, {'item_1', 'item_2'});

    controller.detach(stranger);
    expect(controller.current, isNotNull);
    controller.detach(owner);
    expect(controller.current, isNull);
  });
}
