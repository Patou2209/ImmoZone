import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/message_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/message_model.dart';
import 'conversation_screen.dart';
import 'package:intl/intl.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    if (auth.currentUser != null) {
      await context.read<MessageProvider>().loadUserMessages(auth.currentUser!.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final msgProvider = context.watch<MessageProvider>();
    final userId = auth.currentUser?.id ?? '';
    final conversations = msgProvider.getConversationList(userId);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: AppTheme.primaryColor,
        actions: [
          if (msgProvider.unreadCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${msgProvider.unreadCount} non lus',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: msgProvider.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : conversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.message_outlined, size: 60, color: AppTheme.accentColor),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Aucun message',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                            fontFamily: 'Poppins', color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Contactez un annonceur depuis\nle détail d\'une annonce',
                        style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontFamily: 'Poppins'),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppTheme.accentColor,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: conversations.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
                    itemBuilder: (ctx, i) {
                      final conv = conversations[i];
                      final lastMsg = conv['lastMessage'] as MessageModel;
                      final otherId = conv['otherId'] as String;
                      final otherName = conv['otherName'] as String;
                      final isUnread = !lastMsg.isRead && lastMsg.receiverId == userId;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          radius: 26,
                          backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                          child: Text(
                            otherName.isNotEmpty ? otherName[0].toUpperCase() : '?',
                            style: const TextStyle(fontWeight: FontWeight.w700,
                                color: AppTheme.accentColor, fontFamily: 'Poppins', fontSize: 18),
                          ),
                        ),
                        title: Text(
                          otherName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
                            fontFamily: 'Poppins',
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (lastMsg.propertyTitle != null)
                              Text(
                                lastMsg.propertyTitle!,
                                style: const TextStyle(
                                  fontSize: 11, color: AppTheme.accentColor,
                                  fontFamily: 'Poppins', fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: 2),
                            Text(
                              lastMsg.content,
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'Poppins',
                                color: isUnread ? AppTheme.textPrimary : AppTheme.textSecondary,
                                fontWeight: isUnread ? FontWeight.w600 : FontWeight.w400,
                              ),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatDate(lastMsg.createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'Poppins',
                                color: isUnread ? AppTheme.primaryColor : AppTheme.textHint,
                                fontWeight: isUnread ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                            if (isUnread) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: 10, height: 10,
                                decoration: const BoxDecoration(
                                  color: AppTheme.accentColor, shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ConversationScreen(
                              otherId: otherId,
                              otherName: otherName,
                              propertyId: lastMsg.propertyId,
                              propertyTitle: lastMsg.propertyTitle,
                            ),
                          ),
                        ).then((_) => _load()),
                      );
                    },
                  ),
                ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return DateFormat('HH:mm').format(date);
    if (diff.inDays == 1) return 'Hier';
    if (diff.inDays < 7) return DateFormat('EEE', 'fr').format(date);
    return DateFormat('dd/MM').format(date);
  }
}
