class MessageModel {
  final String id;
  final String senderId;
  final String senderName;
  final String receiverId;
  final String receiverName;
  final String content;
  final String? propertyId;
  final String? propertyTitle;
  final bool isRead;
  final DateTime createdAt;
  final String? attachmentUrl;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.receiverId,
    required this.receiverName,
    required this.content,
    this.propertyId,
    this.propertyTitle,
    this.isRead = false,
    required this.createdAt,
    this.attachmentUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'senderName': senderName,
      'receiverId': receiverId,
      'receiverName': receiverName,
      'content': content,
      'propertyId': propertyId,
      'propertyTitle': propertyTitle,
      'isRead': isRead,
      'createdAt': createdAt.toIso8601String(),
      'attachmentUrl': attachmentUrl,
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'] ?? '',
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? '',
      receiverId: map['receiverId'] ?? '',
      receiverName: map['receiverName'] ?? '',
      content: map['content'] ?? '',
      propertyId: map['propertyId'],
      propertyTitle: map['propertyTitle'],
      isRead: map['isRead'] ?? false,
      createdAt: DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
      attachmentUrl: map['attachmentUrl'],
    );
  }

  MessageModel copyWith({bool? isRead}) {
    return MessageModel(
      id: id,
      senderId: senderId,
      senderName: senderName,
      receiverId: receiverId,
      receiverName: receiverName,
      content: content,
      propertyId: propertyId,
      propertyTitle: propertyTitle,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      attachmentUrl: attachmentUrl,
    );
  }
}
