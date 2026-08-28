library;

/// Provider-neutral whiteboard mutations shared by user and Runtime entry
/// points. These commands intentionally exclude board creation, grouping,
/// connections, search, and arbitrary snapshot replacement.
sealed class WhiteboardDomainCommand {
  const WhiteboardDomainCommand({required this.commandId});

  final String commandId;

  String get kind;
  List<String> get targetCardIds;
  List<String> get targetItemIds;
  Map<String, dynamic> toJson();

  static WhiteboardDomainCommand fromJson(Map<String, dynamic> json) {
    final kind = _requiredString(json, 'kind');
    return switch (kind) {
      'create_card' => CreateCardCommand.fromJson(json),
      'edit_card_title' => EditCardTitleCommand.fromJson(json),
      'edit_card_body' => EditCardBodyCommand.fromJson(json),
      'set_card_labels' => SetCardLabelsCommand.fromJson(json),
      'move_placement' => MovePlacementCommand.fromJson(json),
      'resize_placement' => ResizePlacementCommand.fromJson(json),
      'remove_placement' => RemovePlacementCommand.fromJson(json),
      _ => throw FormatException('Unsupported domain command: $kind'),
    };
  }
}

class CreateCardCommand extends WhiteboardDomainCommand {
  const CreateCardCommand({
    required super.commandId,
    required this.cardId,
    required this.itemId,
    this.title = '',
    this.body = '',
    this.labels = const [],
    this.x = 0,
    this.y = 0,
    this.width = 260,
    this.height = 200,
  });

  factory CreateCardCommand.fromJson(Map<String, dynamic> json) {
    _requireKeys(
      json,
      const {
        'kind',
        'command_id',
        'card_id',
        'item_id',
        'title',
        'body',
        'labels',
        'x',
        'y',
        'width',
        'height',
      },
      const {'kind', 'command_id', 'card_id', 'item_id'},
    );
    return CreateCardCommand(
      commandId: _requiredString(json, 'command_id'),
      cardId: _requiredString(json, 'card_id'),
      itemId: _requiredString(json, 'item_id'),
      title: _optionalString(json['title']) ?? '',
      body: _optionalString(json['body']) ?? '',
      labels: _stringList(json['labels']),
      x: _number(json['x'], 0),
      y: _number(json['y'], 0),
      width: _number(json['width'], 260),
      height: _number(json['height'], 200),
    );
  }

  final String cardId;
  final String itemId;
  final String title;
  final String body;
  final List<String> labels;
  final double x;
  final double y;
  final double width;
  final double height;

  @override
  String get kind => 'create_card';
  @override
  List<String> get targetCardIds => [cardId];
  @override
  List<String> get targetItemIds => [itemId];

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'command_id': commandId,
        'card_id': cardId,
        'item_id': itemId,
        'title': title,
        'body': body,
        'labels': labels,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };
}

/// Manual-surface-only title mutation.
///
/// Runtime does not register this command kind and the facade rejects it at
/// the Runtime authorization boundary. Keeping title separate from
/// [EditCardBodyCommand] prevents a body grant from silently changing Card
/// metadata.
class EditCardTitleCommand extends WhiteboardDomainCommand {
  const EditCardTitleCommand({
    required super.commandId,
    required this.cardId,
    required this.title,
  });

  factory EditCardTitleCommand.fromJson(Map<String, dynamic> json) {
    _requireKeys(
      json,
      const {'kind', 'command_id', 'card_id', 'title'},
      const {'kind', 'command_id', 'card_id', 'title'},
    );
    return EditCardTitleCommand(
      commandId: _requiredString(json, 'command_id'),
      cardId: _requiredString(json, 'card_id'),
      title: _requiredString(json, 'title', allowEmpty: true),
    );
  }

  final String cardId;
  final String title;

  @override
  String get kind => 'edit_card_title';
  @override
  List<String> get targetCardIds => [cardId];
  @override
  List<String> get targetItemIds => const [];
  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'command_id': commandId,
        'card_id': cardId,
        'title': title,
      };
}

/// Replaces the Card's canonical plain-text body projection only.
///
/// It does not replace or rewrite RichTextDocument blocks, marks, or assets.
/// Consumers validate any retained rich document against this projection and
/// hide it as stale until a later body (including Undo) matches exactly.
class EditCardBodyCommand extends WhiteboardDomainCommand {
  const EditCardBodyCommand({
    required super.commandId,
    required this.cardId,
    required this.body,
  });

  factory EditCardBodyCommand.fromJson(Map<String, dynamic> json) {
    _requireKeys(
      json,
      const {'kind', 'command_id', 'card_id', 'body'},
      const {'kind', 'command_id', 'card_id', 'body'},
    );
    return EditCardBodyCommand(
      commandId: _requiredString(json, 'command_id'),
      cardId: _requiredString(json, 'card_id'),
      body: _requiredString(json, 'body', allowEmpty: true),
    );
  }

  final String cardId;
  final String body;
  @override
  String get kind => 'edit_card_body';
  @override
  List<String> get targetCardIds => [cardId];
  @override
  List<String> get targetItemIds => const [];
  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'command_id': commandId,
        'card_id': cardId,
        'body': body,
      };
}

class SetCardLabelsCommand extends WhiteboardDomainCommand {
  const SetCardLabelsCommand({
    required super.commandId,
    required this.cardId,
    required this.labels,
  });

  factory SetCardLabelsCommand.fromJson(Map<String, dynamic> json) {
    _requireKeys(
      json,
      const {'kind', 'command_id', 'card_id', 'labels'},
      const {'kind', 'command_id', 'card_id', 'labels'},
    );
    return SetCardLabelsCommand(
      commandId: _requiredString(json, 'command_id'),
      cardId: _requiredString(json, 'card_id'),
      labels: _stringList(json['labels']),
    );
  }

  final String cardId;
  final List<String> labels;
  @override
  String get kind => 'set_card_labels';
  @override
  List<String> get targetCardIds => [cardId];
  @override
  List<String> get targetItemIds => const [];
  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'command_id': commandId,
        'card_id': cardId,
        'labels': labels,
      };
}

class MovePlacementCommand extends WhiteboardDomainCommand {
  const MovePlacementCommand({
    required super.commandId,
    required this.itemId,
    required this.x,
    required this.y,
  });

  factory MovePlacementCommand.fromJson(Map<String, dynamic> json) {
    _requireKeys(
      json,
      const {'kind', 'command_id', 'item_id', 'x', 'y'},
      const {'kind', 'command_id', 'item_id', 'x', 'y'},
    );
    return MovePlacementCommand(
      commandId: _requiredString(json, 'command_id'),
      itemId: _requiredString(json, 'item_id'),
      x: _requiredNumber(json, 'x'),
      y: _requiredNumber(json, 'y'),
    );
  }

  final String itemId;
  final double x;
  final double y;
  @override
  String get kind => 'move_placement';
  @override
  List<String> get targetCardIds => const [];
  @override
  List<String> get targetItemIds => [itemId];
  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'command_id': commandId,
        'item_id': itemId,
        'x': x,
        'y': y,
      };
}

class ResizePlacementCommand extends WhiteboardDomainCommand {
  const ResizePlacementCommand({
    required super.commandId,
    required this.itemId,
    required this.width,
    required this.height,
  });

  factory ResizePlacementCommand.fromJson(Map<String, dynamic> json) {
    _requireKeys(
      json,
      const {'kind', 'command_id', 'item_id', 'width', 'height'},
      const {'kind', 'command_id', 'item_id', 'width', 'height'},
    );
    return ResizePlacementCommand(
      commandId: _requiredString(json, 'command_id'),
      itemId: _requiredString(json, 'item_id'),
      width: _requiredNumber(json, 'width'),
      height: _requiredNumber(json, 'height'),
    );
  }

  final String itemId;
  final double width;
  final double height;
  @override
  String get kind => 'resize_placement';
  @override
  List<String> get targetCardIds => const [];
  @override
  List<String> get targetItemIds => [itemId];
  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'command_id': commandId,
        'item_id': itemId,
        'width': width,
        'height': height,
      };
}

class RemovePlacementCommand extends WhiteboardDomainCommand {
  const RemovePlacementCommand({
    required super.commandId,
    required this.itemId,
  });

  factory RemovePlacementCommand.fromJson(Map<String, dynamic> json) {
    _requireKeys(
      json,
      const {'kind', 'command_id', 'item_id'},
      const {'kind', 'command_id', 'item_id'},
    );
    return RemovePlacementCommand(
      commandId: _requiredString(json, 'command_id'),
      itemId: _requiredString(json, 'item_id'),
    );
  }

  final String itemId;
  @override
  String get kind => 'remove_placement';
  @override
  List<String> get targetCardIds => const [];
  @override
  List<String> get targetItemIds => [itemId];
  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'command_id': commandId,
        'item_id': itemId,
      };
}

class WhiteboardDomainCommandBatch {
  const WhiteboardDomainCommandBatch({
    required this.operationBatchId,
    required this.boardId,
    required this.commands,
    this.expectedSnapshotHash,
  });

  factory WhiteboardDomainCommandBatch.fromJson(Map<String, dynamic> json) {
    _requireKeys(
      json,
      const {
        'schema_version',
        'operation_batch_id',
        'board_id',
        'expected_snapshot_hash',
        'commands',
      },
      const {'schema_version', 'operation_batch_id', 'board_id', 'commands'},
    );
    if (json['schema_version'] != 1) {
      throw const FormatException('Unsupported command batch schema');
    }
    final raw = json['commands'];
    if (raw is! List) throw const FormatException('commands must be a list');
    return WhiteboardDomainCommandBatch(
      operationBatchId: _requiredString(json, 'operation_batch_id'),
      boardId: _requiredString(json, 'board_id'),
      expectedSnapshotHash: _optionalString(json['expected_snapshot_hash']),
      commands: raw
          .map(
            (value) => WhiteboardDomainCommand.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  final String operationBatchId;
  final String boardId;
  final String? expectedSnapshotHash;
  final List<WhiteboardDomainCommand> commands;

  Map<String, dynamic> toJson() => {
        'schema_version': 1,
        'operation_batch_id': operationBatchId,
        'board_id': boardId,
        if (expectedSnapshotHash != null)
          'expected_snapshot_hash': expectedSnapshotHash,
        'commands': commands.map((command) => command.toJson()).toList(),
      };
}

String _requiredString(
  Map<String, dynamic> json,
  String key, {
  bool allowEmpty = false,
}) {
  final value = json[key];
  if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
    throw FormatException('$key must be a string');
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Expected string');
  return value;
}

List<String> _stringList(Object? value) {
  if (value == null) return const [];
  if (value is! List || value.any((item) => item is! String)) {
    throw const FormatException('Expected string list');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

double _requiredNumber(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite) {
    throw FormatException('$key must be finite');
  }
  return value.toDouble();
}

double _number(Object? value, double fallback) {
  if (value == null) return fallback;
  if (value is! num || !value.isFinite) {
    throw const FormatException('Expected finite number');
  }
  return value.toDouble();
}

void _requireKeys(
  Map<String, dynamic> json,
  Set<String> allowed,
  Set<String> required,
) {
  if (json.keys.any((key) => !allowed.contains(key)) ||
      required.any((key) => !json.containsKey(key))) {
    throw const FormatException('Unexpected command shape');
  }
}
