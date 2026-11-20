import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/themes.dart';

/// The "add a block" bar at the bottom of the editor.
/// Every button has a visible label, so nobody has to guess.
class NoteNavigationBar extends StatelessWidget {
  const NoteNavigationBar({
    super.key,
    this.addText,
    this.addCode,
    this.addImage,
    this.addMarkdown,
    this.scanDoc,
  });

  final void Function()? addText;
  final void Function()? addCode;
  final void Function()? addImage;
  final void Function()? addMarkdown;
  final void Function()? scanDoc;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final items = <(IconData, String, VoidCallback?)>[
      (Icons.notes_rounded, 'Text', addText),
      (Icons.code_rounded, 'Code', addCode),
      (Icons.tag_rounded, 'Markdown', addMarkdown),
      (Icons.image_outlined, 'Image', addImage),
      if (scanDoc != null) (Icons.document_scanner_outlined, 'Scan', scanDoc),
    ];

    return Container(
      decoration: BoxDecoration(
        color: color.surfaceContainerLow,
        border: Border(top: BorderSide(color: color.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  for (final (icon, label, onTap) in items)
                    Expanded(
                      child: _AddBlockButton(
                        icon: icon,
                        label: label,
                        onTap: onTap,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddBlockButton extends StatelessWidget {
  const _AddBlockButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Add a ${label.toLowerCase()} block',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color.primary),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
