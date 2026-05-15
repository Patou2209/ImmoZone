class AppNotification {
  final String id;
  final String userId;       // destinataire
  final String type;         // 'rejet' | 'suppression' | 'approbation' | 'info'
  final String title;
  final String body;
  final String? propertyId;
  final String? propertyTitle;
  final bool isRead;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.propertyId,
    this.propertyTitle,
    this.isRead = false,
    required this.createdAt,
  });

  AppNotification copyWith({
    String? id, String? userId, String? type,
    String? title, String? body,
    String? propertyId, String? propertyTitle,
    bool? isRead, DateTime? createdAt,
  }) => AppNotification(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    type: type ?? this.type,
    title: title ?? this.title,
    body: body ?? this.body,
    propertyId: propertyId ?? this.propertyId,
    propertyTitle: propertyTitle ?? this.propertyTitle,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt ?? this.createdAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'userId': userId, 'type': type,
    'title': title, 'body': body,
    'propertyId': propertyId, 'propertyTitle': propertyTitle,
    'isRead': isRead,
    'createdAt': createdAt.toIso8601String(),
  };

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
    id: m['id'] ?? '',
    userId: m['userId'] ?? '',
    type: m['type'] ?? 'info',
    title: m['title'] ?? '',
    body: m['body'] ?? '',
    propertyId: m['propertyId'],
    propertyTitle: m['propertyTitle'],
    isRead: m['isRead'] ?? false,
    createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
  );
}
