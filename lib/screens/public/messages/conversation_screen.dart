import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/message_provider.dart';
import '../../../models/message_model.dart';
import '../../../core/theme/app_theme.dart';
import 'package:intl/intl.dart';

class ConversationScreen extends StatefulWidget {
  final String otherId;
  final String otherName;
  final String? propertyId;
  final String? propertyTitle;

  const ConversationScreen({
    super.key,
    required this.otherId,
    required this.otherName,
    this.propertyId,
    this.propertyTitle,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<MessageModel> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final msgs = await context.read<MessageProvider>()
        .getConversation(auth.currentUser!.id, widget.otherId);
    if (mounted) {
      setState(() {
        _messages = msgs;
        _loading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

    final auth = context.read<AuthProvider>();
    await context.read<MessageProvider>().sendMessage(
      senderId: auth.currentUser!.id,
      senderName: auth.currentUser!.name,
      receiverId: widget.otherId,
      receiverName: widget.otherName,
      content: text,
      propertyId: widget.propertyId,
      propertyTitle: widget.propertyTitle,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final myId = auth.currentUser?.id ?? '';

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryColor,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              child: Text(
                widget.otherName.isNotEmpty ? widget.otherName[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'Poppins'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.otherName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins', color: Colors.white)),
                  if (widget.propertyTitle != null)
                    Text(
                      widget.propertyTitle!,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white70, fontFamily: 'Poppins'),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Property reference banner
          if (widget.propertyTitle != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFF20202F).withValues(alpha: 0.08),
              child: Row(
                children: [
                  const Icon(Icons.home_outlined, size: 16, color: AppTheme.accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Concernant : ${widget.propertyTitle}',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.accentColor,
                          fontFamily: 'Poppins', fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // Messages
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.chat_bubble_outline,
                                size: 48, color: AppTheme.textHint),
                            const SizedBox(height: 12),
                            Text(
                              'Démarrez la conversation avec\n${widget.otherName}',
                              style: const TextStyle(
                                  fontSize: 13, color: AppTheme.textSecondary,
                                  fontFamily: 'Poppins'),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (ctx, i) {
                          final msg = _messages[i];
                          final isMe = msg.senderId == myId;
                          final showDate = i == 0 ||
                              _messages[i].createdAt.day != _messages[i - 1].createdAt.day;

                          return Column(
                            children: [
                              if (showDate)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      DateFormat('dd MMMM yyyy', 'fr').format(msg.createdAt),
                                      style: const TextStyle(
                                          fontSize: 11, color: AppTheme.textSecondary,
                                          fontFamily: 'Poppins'),
                                    ),
                                  ),
                                ),
                              _MessageBubble(message: msg, isMe: isMe),
                            ],
                          );
                        },
                      ),
          ),

          // Input
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10, offset: const Offset(0, -2))],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Votre message...',
                        hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
                        filled: true,
                        fillColor: AppTheme.backgroundColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: AppTheme.accentColor, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        color: AppTheme.accentColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          bottom: 8,
          left: isMe ? 60 : 0,
          right: isMe ? 0 : 60,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.primaryColor : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'Poppins',
                color: isMe ? Colors.white : AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('HH:mm').format(message.createdAt),
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'Poppins',
                    color: isMe ? Colors.white70 : AppTheme.textHint,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.isRead ? Icons.done_all : Icons.done,
                    size: 12,
                    color: message.isRead ? Colors.lightBlueAccent : Colors.white70,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
