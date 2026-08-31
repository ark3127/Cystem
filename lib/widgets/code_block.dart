import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CodeBlock extends StatefulWidget {
  const CodeBlock({
    super.key,
    required this.code,
    this.language,
  });

  final String code;
  final String? language;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;

  Future<void> _copyCode() async {
    await Clipboard.setData(
      ClipboardData(
        text: widget.code,
      ),
    );

    if (!mounted) return;

    setState(() {
      _copied = true;
    });

    await Future.delayed(
      const Duration(seconds: 2),
    );

    if (!mounted) return;

    setState(() {
      _copied = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language?.isNotEmpty == true
        ? widget.language!
        : 'Code';

    return Container(
      margin: const EdgeInsets.symmetric(
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              12,
              6,
              6,
              6,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium,
                  ),
                ),
                IconButton(
                  tooltip: _copied
                      ? 'Copied!'
                      : 'Copy code',
                  onPressed: _copyCode,
                  icon: Icon(
                    _copied
                        ? Icons.check
                        : Icons.copy_outlined,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              widget.code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
