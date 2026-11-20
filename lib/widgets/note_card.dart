import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../constants/themes.dart';
import '../features/notes/domain/entities/block.dart';
import '../features/notes/domain/entities/language.dart';
import '../features/notes/domain/entities/note.dart';
import '../features/notes/presentation/bloc/note_bloc.dart';
import '../features/notes/presentation/bloc/note_event.dart';
import '../features/notes/presentation/pages/note_page.dart';
import '../helpers/helper_methods.dart';

/// Short display names for code languages on cards.
String languageLabel(Language lang) {
  switch (lang) {
    case Language.cSharp:
      return 'c#';
    case Language.cpp:
      return 'c++';
    case Language.javaScript:
      return 'js';
    case Language.typeScript:
      return 'ts';
    case Language.armAssembly:
      return 'arm asm';
    case Language.x86Assembly:
      return 'x86 asm';
    case Language.pgSql:
      return 'postgres';
    default:
      return lang.name.toLowerCase();
  }
}

class NoteCard extends StatefulWidget {
  final NoteEntity note;
  final bool isTrashView;
  final VoidCallback? onTapOverride;
  final VoidCallback? onRemoveFromGroup;
  final VoidCallback? onDismissed;

  const NoteCard({
    super.key,
    required this.note,
    this.isTrashView = false,
    this.onTapOverride,
    this.onRemoveFromGroup,
    this.onDismissed,
  });

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  bool _hovered = false;

  NoteEntity get note => widget.note;

  /// The first piece of text in the note, for the preview line.
  String? get _textPreview {
    for (final b in note.blocks) {
      if ((b is NoteBlockEntity || b is MarkdownBlockEntity) &&
          (b.text ?? '').trim().isNotEmpty) {
        return b.text!.trim();
      }
    }
    return null;
  }

  CodeBlockEntity? get _codePreview {
    for (final b in note.blocks) {
      if (b is CodeBlockEntity && (b.text ?? '').trim().isNotEmpty) return b;
    }
    return null;
  }

  ImageProvider? get _cover {
    final image = note.blocks.whereType<ImageBlockEntity>().firstOrNull;
    final path = image?.imagePath;
    if (path == null || path.isEmpty) return null;
    if (kIsWeb || path.startsWith('http')) return NetworkImage(path);
    return FileImage(File(path));
  }

  void _open() {
    if (widget.onTapOverride != null) {
      widget.onTapOverride!();
    } else {
      navigateTo(toPage: NotePage(note: note));
    }
  }

  void _update(NoteEntity updated, {required String message}) {
    final bloc = context.read<NoteBloc>();
    final before = note;
    bloc.add(UpdateNoteEvent(updated));
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => bloc.add(UpdateNoteEvent(before)),
        ),
      ));
  }

  void _onDismissed(DismissDirection direction) {
    HapticFeedback.mediumImpact();
    if (direction == DismissDirection.startToEnd) {
      if (widget.isTrashView) {
        _update(note.copyWith(isTrashed: false, clearTrashTimestamp: true),
            message: 'Restored');
      } else if (note.isArchived) {
        _update(note.copyWith(isArchived: false), message: 'Back in your notes');
      } else {
        _update(note.copyWith(isArchived: true, isPinned: false),
            message: 'Archived');
      }
    } else {
      if (widget.isTrashView) {
        context.read<NoteBloc>().add(DeleteNoteEvent(note.id));
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Deleted for good')));
      } else {
        _update(
          note.copyWith(
              isTrashed: true, isPinned: false, trashTimestamp: DateTime.now()),
          message: 'Moved to trash',
        );
      }
    }
    widget.onDismissed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final cover = _cover;
    final code = _codePreview;
    final text = _textPreview;
    final title = note.title.trim();

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: _hovered ? color.surfaceContainer : color.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppBrand.radius),
        border: Border.all(
          color: _hovered
              ? color.primary.withAlpha(120)
              : color.outlineVariant.withAlpha(160),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cover != null)
            Image(
              image: cover,
              height: 96,
              width: double.infinity,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          title.isEmpty ? 'Untitled' : title,
                          style: textTheme.titleSmall?.copyWith(
                            color: title.isEmpty ? tokens.subtle : color.onSurface,
                            fontStyle:
                                title.isEmpty ? FontStyle.italic : FontStyle.normal,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (widget.onRemoveFromGroup != null)
                      IconButton(
                        tooltip: 'Remove from group',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.folder_off_outlined,
                            size: 18, color: tokens.subtle),
                        onPressed: widget.onRemoveFromGroup,
                      )
                    else if (!widget.isTrashView)
                      IconButton(
                        tooltip: note.isPinned ? 'Unpin' : 'Pin to top',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          note.isPinned
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          size: 18,
                          color: note.isPinned ? tokens.pin : tokens.subtle,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          context.read<NoteBloc>().add(UpdateNoteEvent(
                              note.copyWith(isPinned: !note.isPinned)));
                        },
                      ),
                  ],
                ),
                if (text != null) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      text,
                      style: textTheme.bodySmall?.copyWith(
                        color: color.onSurfaceVariant,
                        height: 1.45,
                      ),
                      maxLines: code == null ? 5 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                if (code != null) ...[
                  const SizedBox(height: 8),
                  _CodePreview(block: code),
                ],
                if (note.tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    note.tags.take(4).map((t) => '#$t').join('  '),
                    style: monoStyle(context, size: 11, color: color.primary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      _relativeDate(note.lastModified),
                      style: monoStyle(context, size: 11, color: tokens.subtle),
                    ),
                    if (note.reminder != null) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.alarm_rounded, size: 13, color: tokens.pin),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          DateFormat.MMMd().add_jm().format(note.reminder!.dateTime),
                          style: monoStyle(context, size: 11, color: tokens.pin),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final interactive = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppBrand.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppBrand.radius),
        onTap: _open,
        onHover: (h) => setState(() => _hovered = h),
        child: Semantics(
          label: 'Note: ${title.isEmpty ? 'Untitled' : title}',
          button: true,
          child: card,
        ),
      ),
    );

    return LongPressDraggable<NoteEntity>(
      data: note,
      hapticFeedbackOnStart: true,
      feedback: _DragPreview(title: title.isEmpty ? 'Untitled' : title),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: Dismissible(
        key: ValueKey('dismiss_${note.id}'),
        background: _swipeBackground(
          context,
          color: color.primaryContainer,
          onColor: color.onPrimaryContainer,
          icon: widget.isTrashView
              ? Icons.restore_rounded
              : (note.isArchived ? Icons.unarchive_rounded : Icons.archive_rounded),
          label: widget.isTrashView
              ? 'restore'
              : (note.isArchived ? 'unarchive' : 'archive'),
          alignment: Alignment.centerLeft,
        ),
        secondaryBackground: _swipeBackground(
          context,
          color: color.errorContainer,
          onColor: color.onErrorContainer,
          icon: widget.isTrashView
              ? Icons.delete_forever_rounded
              : Icons.delete_outline_rounded,
          label: widget.isTrashView ? 'delete forever' : 'trash',
          alignment: Alignment.centerRight,
        ),
        confirmDismiss: (direction) async {
          if (!widget.isTrashView || direction != DismissDirection.endToStart) {
            return true;
          }
          return await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Delete for good?'),
                  content: const Text(
                      'This note and its images will be removed from this device. This can\'t be undone.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancel')),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(c).colorScheme.error,
                        foregroundColor: Theme.of(c).colorScheme.onError,
                      ),
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ) ??
              false;
        },
        onDismissed: _onDismissed,
        child: interactive,
      ),
    );
  }

  Widget _swipeBackground(
    BuildContext context, {
    required Color color,
    required Color onColor,
    required IconData icon,
    required String label,
    required Alignment alignment,
  }) {
    final left = alignment == Alignment.centerLeft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppBrand.radius),
      ),
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!left)
            Text(label, style: monoStyle(context, size: 12, color: onColor)),
          if (!left) const SizedBox(width: 8),
          Icon(icon, color: onColor),
          if (left) const SizedBox(width: 8),
          if (left)
            Text(label, style: monoStyle(context, size: 12, color: onColor)),
        ],
      ),
    );
  }
}

String _relativeDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1 && now.day == date.day) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return DateFormat.E().format(date).toLowerCase();
  if (date.year == now.year) return DateFormat.MMMd().format(date);
  return DateFormat.yMMMd().format(date);
}

/// The first few lines of a code block, in code colors.
class _CodePreview extends StatelessWidget {
  const _CodePreview({required this.block});
  final CodeBlockEntity block;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final lines = block.text!.trimRight().split('\n').take(4).join('\n');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: tokens.codeBackground,
        borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            languageLabel(block.language),
            style: monoStyle(context, size: 10, color: tokens.success),
          ),
          const SizedBox(height: 4),
          Text(
            lines,
            style: monoStyle(context, size: 11, color: tokens.subtle)
                .copyWith(height: 1.4),
            maxLines: 4,
            overflow: TextOverflow.fade,
            softWrap: false,
          ),
        ],
      ),
    );
  }
}

/// What follows your finger while dragging a note onto a group.
class _DragPreview extends StatelessWidget {
  const _DragPreview({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Transform.rotate(
        angle: -0.04,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
            border: Border.all(color: color.primary),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(60),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.drive_file_move_outline, size: 16, color: color.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(context, size: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
