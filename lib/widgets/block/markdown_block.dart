import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'block.dart';
import '../custom_icon_button.dart';

class MarkdownBlock extends Block {
  const MarkdownBlock({
    super.key,
    required super.entity,
    super.moveUp,
    super.moveDown,
    super.delete,
    super.onChanged,
  });

  @override
  State<MarkdownBlock> createState() => _MarkdownBlockState();
}

class _MarkdownBlockState extends State<MarkdownBlock> {
  late final TextEditingController _controller;
  bool _isEditing = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.entity.text);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && mounted) {
        setState(() {
          _isEditing = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    Icon(Icons.description_rounded, size: 20, color: color.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Markdown',
                        style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (widget.delete != null)
                      CustomIconButton(
                        icon: Icons.delete,
                        iconSize: 15,
                        innerColor: color.onError,
                        iconColor: color.error,
                        onPressed: () {
                          widget.delete?.call(widget.id);
                        },
                      ),
                    if (widget.moveUp != null)
                      CustomIconButton(
                        icon: Icons.arrow_upward,
                        iconSize: 15,
                        onPressed: () {
                          widget.moveUp?.call(widget.id);
                        },
                      ),
                    if (widget.moveDown != null)
                      CustomIconButton(
                        icon: Icons.arrow_downward,
                        iconSize: 15,
                        onPressed: () {
                          widget.moveDown?.call(widget.id);
                        },
                      )
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              if (!_isEditing) {
                setState(() {
                  _isEditing = true;
                });
                _focusNode.requestFocus();
              }
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _isEditing
                  ? TextField(
                      key: const ValueKey('editing'),
                      controller: _controller,
                      focusNode: _focusNode,
                      onChanged: (val) {
                        if (widget.onChanged != null) {
                          widget.onChanged!(widget.entity.copyWith(text: val));
                        }
                      },
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: 'Write markdown...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: color.outline.withAlpha(127)),
                        ),
                        filled: true,
                        fillColor: color.surfaceContainerHighest.withAlpha(51),
                      ),
                      style: textTheme.bodyLarge!.copyWith(fontFamily: 'monospace'),
                      keyboardType: TextInputType.multiline,
                    )
                  : Container(
                      key: const ValueKey('preview'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: color.surfaceContainerHighest.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.outline.withAlpha(25)),
                      ),
                      child: MarkdownBody(
                        data: _controller.text.isEmpty ? '*Click to edit markdown...*' : _controller.text,
                        selectable: true,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
