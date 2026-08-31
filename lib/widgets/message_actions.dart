import 'package:flutter/material.dart';

class MessageActions extends StatelessWidget {
  const MessageActions({
    super.key,
    required this.isUser,
    required this.onCopy,
    this.onEdit,
    this.onRegenerate,
    required this.onDelete,
  });

  final bool isUser;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MessageAction>(
      tooltip: 'Message actions',
      icon: const Icon(Icons.more_vert),
      onSelected: (_MessageAction action) {
        switch (action) {
          case _MessageAction.copy:
            onCopy();
            break;

          case _MessageAction.edit:
            onEdit?.call();
            break;

          case _MessageAction.regenerate:
            onRegenerate?.call();
            break;

          case _MessageAction.delete:
            onDelete();
            break;
        }
      },
      itemBuilder: (context) {
        final actions = <PopupMenuEntry<_MessageAction>>[
          const PopupMenuItem(
            value: _MessageAction.copy,
            child: ListTile(
              leading: Icon(Icons.copy_outlined),
              title: Text('Copy'),
            ),
          ),
        ];

        if (isUser) {
          actions.add(
            const PopupMenuItem(
              value: _MessageAction.edit,
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Edit'),
              ),
            ),
          );
        } else {
          actions.add(
            const PopupMenuItem(
              value: _MessageAction.regenerate,
              child: ListTile(
                leading: Icon(Icons.refresh),
                title: Text('Regenerate'),
              ),
            ),
          );
        }

        actions.add(
          const PopupMenuItem(
            value: _MessageAction.delete,
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('Delete'),
            ),
          ),
        );

        return actions;
      },
    );
  }
}

enum _MessageAction {
  copy,
  edit,
  regenerate,
  delete,
}
