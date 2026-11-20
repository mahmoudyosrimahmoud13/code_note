import 'package:flutter/material.dart';

import '../../constants/themes.dart';

/// One action in a block's "more" menu.
class BlockAction {
  const BlockAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;
}

/// The shared header every block uses: a small type label on the left,
/// quick actions and one "more" menu on the right.
///
/// Delete and reorder live inside the menu, so the most dangerous button is
/// never sitting in the open, and the content gets the space.
class BlockHeader extends StatelessWidget {
  const BlockHeader({
    super.key,
    required this.label,
    required this.icon,
    this.leading,
    this.quickActions = const [],
    this.onMoveUp,
    this.onMoveDown,
    this.onDelete,
    this.extraActions = const [],
  });

  final String label;
  final IconData icon;

  /// Replaces the label, for example the language picker on code blocks.
  final Widget? leading;
  final List<Widget> quickActions;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onDelete;
  final List<BlockAction> extraActions;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final subtle = context.tokens.subtle;

    final actions = <BlockAction>[
      ...extraActions,
      if (onMoveUp != null)
        BlockAction(
            label: 'Move up', icon: Icons.arrow_upward_rounded, onTap: onMoveUp!),
      if (onMoveDown != null)
        BlockAction(
            label: 'Move down',
            icon: Icons.arrow_downward_rounded,
            onTap: onMoveDown!),
      if (onDelete != null)
        BlockAction(
          label: 'Delete block',
          icon: Icons.delete_outline_rounded,
          onTap: onDelete!,
          destructive: true,
        ),
    ];

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: leading ??
                Row(children: [
                  Icon(icon, size: 16, color: subtle),
                  const SizedBox(width: 6),
                  Text(label, style: monoStyle(context, size: 12, color: subtle)),
                ]),
          ),
          ...quickActions,
          if (actions.isNotEmpty)
            PopupMenuButton<int>(
              tooltip: 'More actions',
              icon: Icon(Icons.more_horiz_rounded, color: subtle, size: 20),
              onSelected: (i) => actions[i].onTap(),
              itemBuilder: (context) => [
                for (var i = 0; i < actions.length; i++) ...[
                  if (actions[i].destructive && i > 0) const PopupMenuDivider(),
                  PopupMenuItem<int>(
                    value: i,
                    child: Row(children: [
                      Icon(actions[i].icon,
                          size: 18,
                          color: actions[i].destructive
                              ? color.error
                              : color.onSurface),
                      const SizedBox(width: 12),
                      Text(actions[i].label,
                          style: TextStyle(
                              color: actions[i].destructive
                                  ? color.error
                                  : color.onSurface)),
                    ]),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

/// A small, quiet icon button for the block header.
class BlockQuickAction extends StatelessWidget {
  const BlockQuickAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 18, color: context.tokens.subtle),
    );
  }
}
