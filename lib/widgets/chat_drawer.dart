import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/chat_conversation.dart';

class ChatDrawer extends StatefulWidget {
  const ChatDrawer({
    super.key,
    required this.conversations,
    required this.currentConversationId,
    required this.onNewChat,
    required this.onSelectConversation,
    required this.onTogglePin,
    required this.onRenameConversation,
    required this.onDeleteConversation,
    required this.onOpenSettings,
  });

  final List<ChatConversation> conversations;
  final String? currentConversationId;
  final VoidCallback onNewChat;
  final ValueChanged<ChatConversation> onSelectConversation;
  final ValueChanged<ChatConversation> onTogglePin;
  final ValueChanged<ChatConversation> onRenameConversation;
  final ValueChanged<ChatConversation> onDeleteConversation;
  final VoidCallback onOpenSettings;

  @override
  State<ChatDrawer> createState() => _ChatDrawerState();
}

class _ChatDrawerState extends State<ChatDrawer> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() => _query = _searchController.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chats = widget.conversations.where((chat) => _query.isEmpty || chat.title.toLowerCase().contains(_query)).toList();
    chats.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    final pinned = chats.where((chat) => chat.isPinned).toList();
    final recent = chats.where((chat) => !chat.isPinned).toList();

    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.84,
      backgroundColor: AppTheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: Row(children: [
                Container(width: 38, height: 38, decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.12), shape: BoxShape.circle), child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.primary, size: 19)),
                const SizedBox(width: 11),
                const Expanded(child: Text('CYSTEM', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 0.2))),
                IconButton(tooltip: 'New chat', onPressed: widget.onNewChat, icon: const Icon(Icons.edit_rounded, size: 21)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(hintText: 'Search chats', prefixIcon: const Icon(Icons.search_rounded, size: 20), suffixIcon: _query.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: _searchController.clear)),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                children: [
                  if (pinned.isNotEmpty) ...[
                    const _SectionTitle(title: 'Pinned'),
                    ...pinned.map(_buildTile),
                    const SizedBox(height: 10),
                  ],
                  if (recent.isNotEmpty) ...[
                    const _SectionTitle(title: 'Recent'),
                    ...recent.map(_buildTile),
                  ],
                  if (chats.isEmpty)
                    Padding(padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20), child: Column(children: [const Icon(Icons.search_off_rounded, size: 28, color: AppTheme.textMuted), const SizedBox(height: 10), Text(_query.isEmpty ? 'No chats yet' : 'No matching chats', style: Theme.of(context).textTheme.bodyMedium)])),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  onTap: widget.onOpenSettings,
                  child: const Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 13), child: Row(children: [Icon(Icons.settings_outlined, size: 21), SizedBox(width: 13), Expanded(child: Text('Settings', style: TextStyle(fontWeight: FontWeight.w600))), Icon(Icons.chevron_right_rounded, size: 19)])),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(ChatConversation conversation) {
    final selected = conversation.id == widget.currentConversationId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? AppTheme.primary.withValues(alpha: 0.13) : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => widget.onSelectConversation(conversation),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
            child: Row(children: [
              Icon(conversation.isPinned ? Icons.push_pin_rounded : Icons.chat_bubble_outline_rounded, size: 18, color: selected ? AppTheme.primary : AppTheme.textSecondary),
              const SizedBox(width: 11),
              Expanded(child: Text(conversation.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? AppTheme.textPrimary : AppTheme.textSecondary, fontWeight: selected ? FontWeight.w600 : FontWeight.w500))),
              SizedBox(width: 34, height: 34, child: PopupMenuButton<_ConversationAction>(padding: EdgeInsets.zero, tooltip: 'Chat options', onSelected: (action) {
                switch (action) {
                  case _ConversationAction.pin: widget.onTogglePin(conversation); break;
                  case _ConversationAction.rename: widget.onRenameConversation(conversation); break;
                  case _ConversationAction.delete: widget.onDeleteConversation(conversation); break;
                }
              }, itemBuilder: (_) => [
                PopupMenuItem(value: _ConversationAction.pin, child: Text(conversation.isPinned ? 'Unpin' : 'Pin')),
                const PopupMenuItem(value: _ConversationAction.rename, child: Text('Rename')),
                const PopupMenuItem(value: _ConversationAction.delete, child: Text('Delete')),
              ], child: const Icon(Icons.more_horiz_rounded, size: 19))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.fromLTRB(12, 7, 12, 7), child: Text(title, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.2)));
  }
}

enum _ConversationAction { pin, rename, delete }
