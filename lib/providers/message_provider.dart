import 'package:flutter/material.dart';
import '../models/message_model.dart';
import '../services/data_service.dart';

class MessageProvider extends ChangeNotifier {
  final DataService _dataService = DataService();
  List<MessageModel> _messages = [];
  bool _isLoading = false;

  List<MessageModel> get messages => _messages;
  bool get isLoading => _isLoading;

  int get unreadCount => _messages.where((m) => !m.isRead).length;

  Future<void> loadUserMessages(String userId) async {
    _isLoading = true;
    notifyListeners();
    _messages = await _dataService.getUserMessages(userId);
    _isLoading = false;
    notifyListeners();
  }

  Future<List<MessageModel>> getConversation(
      String userId, String otherId) async {
    return await _dataService.getConversation(userId, otherId);
  }

  Future<void> sendMessage({
    required String senderId,
    required String senderName,
    required String receiverId,
    required String receiverName,
    required String content,
    String? propertyId,
    String? propertyTitle,
  }) async {
    final message = MessageModel(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      senderId: senderId,
      senderName: senderName,
      receiverId: receiverId,
      receiverName: receiverName,
      content: content,
      propertyId: propertyId,
      propertyTitle: propertyTitle,
      createdAt: DateTime.now(),
    );
    await _dataService.sendMessage(message);
    await loadUserMessages(senderId);
  }

  List<Map<String, dynamic>> getConversationList(String userId) {
    final Map<String, MessageModel> lastMessages = {};
    for (final msg in _messages) {
      final otherId =
          msg.senderId == userId ? msg.receiverId : msg.senderId;
      if (!lastMessages.containsKey(otherId) ||
          msg.createdAt.isAfter(lastMessages[otherId]!.createdAt)) {
        lastMessages[otherId] = msg;
      }
    }
    return lastMessages.entries.map((e) {
      final msg = e.value;
      final otherId = msg.senderId == userId ? msg.receiverId : msg.senderId;
      final otherName =
          msg.senderId == userId ? msg.receiverName : msg.senderName;
      return {
        'otherId': otherId,
        'otherName': otherName,
        'lastMessage': msg,
      };
    }).toList()
      ..sort((a, b) => (b['lastMessage'] as MessageModel)
          .createdAt
          .compareTo((a['lastMessage'] as MessageModel).createdAt));
  }
}
