import 'package:flutter/material.dart';

import '../models/chat_conversation.dart';
import 'conversation_tile.dart';

class ChatDrawer extends StatelessWidget {
  const ChatDrawer({
    super.key,
    required this.conversations,
    required this.currentConversationId,
    required this.onNewChat,
    required this.onSelectConversation,
    required this.onTogglePin,
    required this.onOpenSettings,
  });

  final List<ChatConversation> conversations;
  final String? currentConversationId;

  final VoidCallback onNewChat;
  final ValueChanged<ChatConversation>
      onSelectConversation;
  final ValueChanged<ChatConversation>
      onTogglePin;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final pinned = conversations
        .where((conversation) => conversation.isPinned)
        .toList();

    final recent = conversations
        .where((conversation) => !conversation.isPinned)
        .toList();

    pinned.sort(
      (a, b) => b.updatedAt.compareTo(a.updatedAt),
    );

    recent.sort(
      (a, b) => b.updatedAt.compareTo(a.updatedAt),
    );

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'CYSTEM',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.settings_outlined,
                    ),
                    tooltip: 'Settings',
                    onPressed: onOpenSettings,
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onNewChat,
                  icon: const Icon(Icons.add),
                  label: const Text('New chat'),
                ),
              ),
            ),

            const SizedBox(height: 12),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                ),
                children: [
                  if (pinned.isNotEmpty) ...[
                    const _SectionTitle(
                      title: 'PINNED',
                    ),
                    ...pinned.map(
                      (conversation) => ConversationTile(
                        conversation: conversation,
                        isSelected:
                            conversation.id ==
                                currentConversationId,
                        onTap: () =>
                            onSelectConversation(
                          conversation,
                        ),
                        onPin: () =>
                            onTogglePin(
                          conversation,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (recent.isNotEmpty) ...[
                    const _SectionTitle(
                      title: 'RECENT',
                    ),
                    ...recent.map(
                      (conversation) => ConversationTile(
                        conversation: conversation,
                        isSelected:
                            conversation.id ==
                                currentConversationId,
                        onTap: () =>
                            onSelectConversation(
                          conversation,
                        ),
                        onPin: () =>
                            onTogglePin(
                          conversation,
                        ),
                      ),
                    ),
                  ],

                  if (conversations.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No conversations yet.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),

            const Divider(height: 1),

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
        16,
        16,
        16,
        6,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color:
              Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
