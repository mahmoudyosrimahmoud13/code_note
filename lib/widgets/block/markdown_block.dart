import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/themes.dart';
import 'block.dart';
import 'block_frame.dart';

/// A markdown block: shows the rendered result, tap to edit the source.
class MarkdownBlock extends Block {
  const MarkdownBlock({
    super.key,
    required super.entity,
    super.moveUp,
    super.moveDown,
    super.delete,
    super.onChanged,
    super.dragHandle,
  });

  @override
  State<MarkdownBlock> createState() => _MarkdownBlockState();
}

class _MarkdownBlockState extends State<MarkdownBlock> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.entity.text);
    // New, empty blocks open ready to type.
    _isEditing = (widget.entity.text ?? '').isEmpty;
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && mounted && _controller.text.isNotEmpty) {
        setState(() => _isEditing = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() => _isEditing = true);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BlockHeader(
              handle: widget.dragHandle,
            label: 'markdown',
            icon: Icons.tag_rounded,
            quickActions: [
              BlockQuickAction(
                icon: _isEditing ? Icons.visibility_rounded : Icons.edit_rounded,
                tooltip: _isEditing ? 'Preview' : 'Edit',
                onPressed: () => _isEditing
                    ? setState(() => _isEditing = false)
                    : _startEditing(),
              ),
            ],
            onMoveUp: widget.moveUp == null ? null : () => widget.moveUp!(widget.id),
            onMoveDown:
                widget.moveDown == null ? null : () => widget.moveDown!(widget.id),
            onDelete: widget.delete == null ? null : () => widget.delete!(widget.id),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isEditing
                ? TextField(
                    key: const ValueKey('editing'),
                    controller: _controller,
                    focusNode: _focusNode,
                    onChanged: (val) =>
                        widget.onChanged?.call(widget.entity.copyWith(text: val)),
                    maxLines: null,
                    minLines: 3,
                    decoration: const InputDecoration(
                      hintText: '# Heading\n- a list\n**bold**, `code`',
                    ),
                    style: monoStyle(context, size: 13.5),
                    keyboardType: TextInputType.multiline,
                  )
                : Material(
                    key: const ValueKey('preview'),
                    color: color.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
                      onTap: _startEditing,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: MarkdownBody(
                          data: _controller.text,
                          selectable: false,
                          onTapLink: (text, href, title) {
                            if (href != null) {
                              launchUrl(Uri.parse(href),
                                  mode: LaunchMode.externalApplication);
                            }
                          },
                          styleSheet:
                              MarkdownStyleSheet.fromTheme(Theme.of(context))
                                  .copyWith(
                            p: textTheme.bodyLarge,
                            code: monoStyle(context, size: 13,
                                color: color.primary),
                            codeblockDecoration: BoxDecoration(
                              color: context.tokens.codeBackground,
                              borderRadius:
                                  BorderRadius.circular(AppBrand.radiusSmall),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
