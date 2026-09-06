import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class MessageActions extends StatelessWidget {
  const MessageActions({super.key, required this.isUser, required this.onCopy, this.onEdit, this.onRegenerate, required this.onDelete});

  final bool isUser;
  final VoidCallback? onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MessageAction>(
      tooltip: 'Message actions',
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_horiz_rounded, size: 19, color: AppTheme.textMuted),
      onSelected: (action) {
        switch (action) {
          case _MessageAction.copy: onCopy?.call(); break;
          case _MessageAction.edit: onEdit?.call(); break;
          case _MessageAction.regenerate: onRegenerate?.call(); break;
          case _MessageAction.delete: onDelete(); break;
        }
      },
      itemBuilder: (_) {
        final actions = <PopupMenuEntry<_MessageAction>>[];
        if (onCopy != null) actions.add(const PopupMenuItem(value: _MessageAction.copy, child: Text('Copy')));
        if (isUser && onEdit != null) actions.add(const PopupMenuItem(value: _MessageAction.edit, child: Text('Edit')));
        if (!isUser && onRegenerate != null) actions.add(const PopupMenuItem(value: _MessageAction.regenerate, child: Text('Regenerate')));
        actions.add(const PopupMenuItem(value: _MessageAction.delete, child: Text('Delete')));
        return actions;
      },
    );
  }
}

enum _MessageAction { copy, edit, regenerate, delete }
