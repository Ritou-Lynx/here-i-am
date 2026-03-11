class CalendarCard {
  final String id;
  final int timestamp;
  final String title;
  final List<String> tags;
  final String location;

  CalendarCard({
    required this.id,
    required this.timestamp,
    required this.title,
    this.tags = const [],
    this.location = '',
  });

  factory CalendarCard.fromJson(Map<String, dynamic> json) {
    var tagsData = json['tags'];
    List<String> parsedTags = [];
    if (tagsData is List) {
      parsedTags = tagsData.map((e) => e.toString()).toList();
    } else if (tagsData is String) {
      parsedTags = [tagsData];
    }

    return CalendarCard(
      id: json['id'] as String? ?? '',
      timestamp: json['timestamp'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      tags: parsedTags,
      location: json['location'] as String? ?? '',
    );
  }
}

class CalendarDay {
  final int timestamp;
  final List<CalendarCard> cards;
  final int total;

  CalendarDay({
    required this.timestamp,
    required this.cards,
    required this.total,
  });

  factory CalendarDay.fromJson(Map<String, dynamic> json) {
    return CalendarDay(
      timestamp: json['timestamp'] as int? ?? 0,
      cards: (json['cards'] as List<dynamic>? ?? const [])
          .map((e) => CalendarCard.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
    );
  }
}
