import 'package:flutter/material.dart';

import '../models/chat_conversation.dart';

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.isSelected,
    required this.onTap,
    required this.onPin,
  });

  final ChatConversation conversation;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: isSelected,
      selectedTileColor:
          Theme.of(context).colorScheme.primary.withValues(
                alpha: 0.12,
              ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
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
      trailing: IconButton(
        icon: Icon(
          conversation.isPinned
              ? Icons.push_pin
              : Icons.push_pin_outlined,
        ),
        tooltip: conversation.isPinned
            ? 'Unpin chat'
            : 'Pin chat',
        onPressed: onPin,
      ),
      onTap: onTap,
    );
  }
}
