class ShortcutItem {
  final String id;
  final String name;
  final String content;
  final String type; // 'text', 'action' etc.

  const ShortcutItem({
    required this.id,
    required this.name,
    required this.content,
    this.type = 'text',
  });

  factory ShortcutItem.fromJson(Map<String, dynamic> json) {
    return ShortcutItem(
      id: json['id'] as String,
      name: json['name'] as String,
      content: json['content'] as String,
      type: json['type'] as String? ?? 'text',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'content': content,
      'type': type,
    };
  }
}
