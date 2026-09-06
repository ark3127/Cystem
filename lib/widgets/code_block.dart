import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../core/theme/app_theme.dart';

class CodeBlock extends StatefulWidget {
  const CodeBlock({super.key, required this.code, this.language});
  final String code;
  final String? language;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language?.trim().isNotEmpty == true ? widget.language!.trim() : 'Code';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: AppTheme.surfaceRaised, borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 7, 6, 7),
          child: Row(children: [
            const Icon(Icons.code_rounded, size: 15, color: AppTheme.textMuted),
            const SizedBox(width: 7),
            Expanded(child: Text(language, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600))),
            SizedBox(width: 34, height: 34, child: IconButton(padding: EdgeInsets.zero, tooltip: _copied ? 'Copied' : 'Copy code', onPressed: _copyCode, icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 16, color: _copied ? AppTheme.primary : AppTheme.textSecondary))),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFF29292E)),
        SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(14, 13, 14, 15), child: SelectableText(widget.code, style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5, color: AppTheme.textPrimary))),
      ]),
    );
  }
}

class CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) => CodeBlock(code: text.text);
}
