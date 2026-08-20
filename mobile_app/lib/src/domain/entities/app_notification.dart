class AppNotification {
  final String id;
  final String title;
  final String summary;
  final String description;
  final String type; // 'info', 'success', 'warning', 'error'
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.summary,
    required this.description,
    required this.type,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      title: json['title'] as String,
      summary: json['summary'] as String,
      description: json['description'] as String,
      type: json['type'] as String? ?? 'info',
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      title: title,
      summary: summary,
      description: description,
      type: type,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}
