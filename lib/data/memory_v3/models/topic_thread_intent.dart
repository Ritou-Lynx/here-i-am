import 'dart:convert';

/// A lightweight reference linking a Book or Manga to a Topic Thread.
///
/// Stored as JSON array in Books.intentsJson / ComicMangas.intentsJson.
/// Example: [{"threadId":"uuid","threadTitle":"CP类型偏好"}]
class TopicThreadIntentItem {
  final String threadId;
  final String threadTitle;

  const TopicThreadIntentItem({
    required this.threadId,
    required this.threadTitle,
  });

  factory TopicThreadIntentItem.fromJson(Map<String, dynamic> json) =>
      TopicThreadIntentItem(
        threadId: json['threadId'] as String? ?? '',
        threadTitle: json['threadTitle'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'threadId': threadId,
        'threadTitle': threadTitle,
      };

  static List<TopicThreadIntentItem> parseList(String json) {
    if (json == '[]' || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(TopicThreadIntentItem.fromJson)
          .where((e) => e.threadId.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String encodeList(List<TopicThreadIntentItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());
}
