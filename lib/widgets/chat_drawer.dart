import 'package:flutter/material.dart';

import '../models/chat_conversation.dart';

class ChatDrawer extends StatelessWidget {
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
  final ValueChanged<ChatConversation>
      onSelectConversation;
  final ValueChanged<ChatConversation>
      onTogglePin;
  final ValueChanged<ChatConversation>
      onRenameConversation;
  final ValueChanged<ChatConversation>
      onDeleteConversation;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final sortedConversations =
        List<ChatConversation>.from(
      conversations,
    );

    sortedConversations.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }

      return b.updatedAt.compareTo(a.updatedAt);
    });

    final pinnedChats = sortedConversations
        .where((chat) => chat.isPinned)
        .toList();

    final regularChats = sortedConversations
        .where((chat) => !chat.isPinned)
        .toList();

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                ),
                children: [
                  if (pinnedChats.isNotEmpty) ...[
                    const _SectionTitle(
                      title: 'Pinned',
                    ),
                    ...pinnedChats.map(
                      (conversation) =>
                          _ConversationTile(
                        conversation: conversation,
                        isSelected:
                            conversation.id ==
                                currentConversationId,
                        onTap: () =>
                            onSelectConversation(
                          conversation,
                        ),
                        onTogglePin: () =>
                            onTogglePin(
                          conversation,
                        ),
                        onRename: () =>
                            onRenameConversation(
                          conversation,
                        ),
                        onDelete: () =>
                            onDeleteConversation(
                          conversation,
                        ),
                      ),
                    ),
                    const Divider(),
                  ],

                  if (regularChats.isNotEmpty) ...[
                    const _SectionTitle(
                      title: 'Chats',
                    ),
                    ...regularChats.map(
                      (conversation) =>
                          _ConversationTile(
                        conversation: conversation,
                        isSelected:
                            conversation.id ==
                                currentConversationId,
                        onTap: () =>
                            onSelectConversation(
                          conversation,
                        ),
                        onTogglePin: () =>
                            onTogglePin(
                          conversation,
                        ),
                        onRename: () =>
                            onRenameConversation(
                          conversation,
                        ),
                        onDelete: () =>
                            onDeleteConversation(
                          conversation,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const Divider(),

            ListTile(
              leading: const Icon(
                Icons.settings_outlined,
              ),
              title: const Text('Settings'),
              onTap: onOpenSettings,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'CYSTEM',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          IconButton(
            tooltip: 'New chat',
            onPressed: onNewChat,
            icon: const Icon(
              Icons.edit_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        12,
        16,
        6,
      ),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.isSelected,
    required this.onTap,
    required this.onTogglePin,
    required this.onRename,
    required this.onDelete,
  });

  final ChatConversation conversation;
  final bool isSelected;

  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: isSelected,
      selectedTileColor: Theme.of(context)
          .colorScheme
          .primaryContainer,
      leading: Icon(
        conversation.isPinned
            ? Icons.push_pin
            : Icons.chat_bubble_outline,
      ),
      title: Text(
        conversation.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
      trailing: PopupMenuButton<_ConversationAction>(
        tooltip: 'Chat options',
        onSelected: (action) {
          switch (action) {
            case _ConversationAction.pin:
              onTogglePin();
              break;

            case _ConversationAction.rename:
              onRename();
              break;

            case _ConversationAction.delete:
              onDelete();
              break;
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _ConversationAction.pin,
            child: ListTile(
              leading: Icon(
                conversation.isPinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin,
              ),
              title: Text(
                conversation.isPinned
                    ? 'Unpin'
                    : 'Pin',
              ),
            ),
          ),
          const PopupMenuItem(
            value: _ConversationAction.rename,
            child: ListTile(
              leading: Icon(
                Icons.edit_outlined,
              ),
              title: Text('Rename'),
            ),
          ),
          const PopupMenuItem(
            value: _ConversationAction.delete,
            child: ListTile(
              leading: Icon(
                Icons.delete_outline,
              ),
              title: Text('Delete'),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ConversationAction {
  pin,
  rename,
  delete,
}
