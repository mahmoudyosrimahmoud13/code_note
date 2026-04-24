import 'dart:io';

import 'package:code_note/helpers/helper_methods.dart';
import 'package:code_note/features/notes/domain/entities/note.dart';
import 'package:code_note/features/notes/domain/entities/block.dart';
import 'package:code_note/features/notes/presentation/pages/note_page.dart';
import 'package:code_note/features/notes/presentation/bloc/note_bloc.dart';
import 'package:code_note/features/notes/presentation/bloc/note_event.dart';
import 'package:code_note/features/notes/presentation/bloc/note_group_bloc.dart';
import 'package:code_note/features/notes/presentation/bloc/note_group_event.dart';
import 'package:code_note/widgets/animated_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

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

class _NoteCardState extends State<NoteCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  DateTime get lastModified => widget.note.lastModified;
  String? get title => widget.note.title;

  String get body {
    final noteBlock = widget.note.blocks.whereType<NoteBlockEntity>().firstOrNull;
    if (noteBlock?.text != null && noteBlock!.text!.isNotEmpty) {
      return noteBlock.text!;
    }
    final codeBlock = widget.note.blocks.whereType<CodeBlockEntity>().firstOrNull;
    if (codeBlock?.text != null && codeBlock!.text!.isNotEmpty) {
      return codeBlock.text!;
    }
    return 'Empty note';
  }

  ImageProvider? get imageProvider {
    final imageBlock = widget.note.blocks.whereType<ImageBlockEntity>().firstOrNull;
    if (imageBlock?.imagePath != null) {
      if (kIsWeb) {
        return NetworkImage(imageBlock!.imagePath!);
      } else {
        return FileImage(File(imageBlock!.imagePath!));
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final textTheme = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;

    final cardContent = MouseRegion(
      onEnter: (_) => _controller.forward(),
      onExit: (_) => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: color.surfaceContainerHighest.withAlpha(50),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.outlineVariant.withAlpha(50)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          width: double.infinity,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (imageProvider != null)
                    Container(
                      width: double.infinity,
                      height: size.height * 0.15,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                        image: DecorationImage(
                          image: imageProvider!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (title != null && title!.isNotEmpty)
                              Expanded(
                                child: Text(
                                  title!,
                                  style: textTheme.titleSmall!.copyWith(
                                    color: color.onSurface,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                        if (widget.note.tags.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: widget.note.tags.take(3).map((tag) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    color.secondaryContainer.withAlpha(150),
                                    color.secondaryContainer.withAlpha(100),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '#$tag',
                                style: textTheme.labelSmall!.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: color.onSecondaryContainer,
                                ),
                              ),
                            )).toList(),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          body,
                          style: textTheme.bodySmall!.copyWith(
                            color: color.onSurfaceVariant,
                            height: 1.4,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.access_time_rounded, size: 12, color: color.outline.withAlpha(150)),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      DateFormat.yMMMd().format(lastModified),
                                      style: textTheme.labelSmall!.copyWith(
                                        color: color.outline,
                                        fontSize: 10,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.note.reminder != null)
                              Flexible(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      PulsingIcon(icon: Icons.notifications_active_rounded, size: 12, color: color.primary),
                                      const SizedBox(width: 2),
                                      Flexible(
                                        child: Text(
                                          DateFormat.jm().format(widget.note.reminder!.dateTime),
                                          style: textTheme.labelSmall!.copyWith(
                                            color: color.primary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (widget.note.blocks.any((b) => b is CodeBlockEntity))
                              GlowingIcon(icon: Icons.code_rounded, size: 14, color: color.primary),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (widget.onRemoveFromGroup != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: color.errorContainer.withAlpha(200),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close_rounded, size: 12, color: color.onErrorContainer),
                    ),
                    onPressed: widget.onRemoveFromGroup,
                    tooltip: 'Remove from Group',
                  ),
                ),
              if (widget.onRemoveFromGroup == null && !widget.isTrashView)
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (child, animation) {
                        return RotationTransition(
                          turns: Tween(begin: 0.75, end: 1.0).animate(
                            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                          ),
                          child: ScaleTransition(scale: animation, child: child),
                        );
                      },
                      child: Icon(
                        widget.note.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                        key: ValueKey(widget.note.isPinned),
                        size: 18,
                        color: widget.note.isPinned ? Colors.amber.shade600 : color.outline.withAlpha(150),
                      ),
                    ),
                    onPressed: () {
                      context.read<NoteBloc>().add(UpdateNoteEvent(widget.note.copyWith(isPinned: !widget.note.isPinned)));
                    },
                    tooltip: widget.note.isPinned ? 'Unpin Note' : 'Pin Note',
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Hero(
      tag: 'note_${widget.note.id}',
      child: LongPressDraggable<NoteEntity>(
        data: widget.note,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: 150,
            child: Opacity(
              opacity: 0.8,
              child: cardContent,
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: cardContent,
        ),
        child: Dismissible(
          key: ValueKey('dismiss_${widget.note.id}'),
          background: _buildDismissBackground(
            color: widget.isTrashView 
                ? color.primary 
                : (widget.note.isArchived ? color.primary : color.secondary),
            icon: widget.isTrashView 
                ? Icons.restore_rounded 
                : (widget.note.isArchived ? Icons.unarchive_rounded : Icons.archive_rounded),
            alignment: Alignment.centerLeft,
            onColor: widget.isTrashView 
                ? color.onPrimary 
                : (widget.note.isArchived ? color.onPrimary : color.onSecondary),
          ),
          secondaryBackground: _buildDismissBackground(
            color: color.error,
            icon: widget.isTrashView ? Icons.delete_forever_rounded : Icons.delete_rounded,
            alignment: Alignment.centerRight,
            onColor: color.onError,
          ),
          onDismissed: (direction) {
            if (direction == DismissDirection.startToEnd) {
              // Swipe Right: Positive Actions (Restore / Archive / Dearchive)
              if (widget.isTrashView) {
                // Restore from Trash
                context.read<NoteBloc>().add(UpdateNoteEvent(widget.note.copyWith(
                  isDeleted: false,
                )));
              } else {
                if (widget.note.isArchived) {
                  // Dearchive: Back to Home
                  context.read<NoteBloc>().add(UpdateNoteEvent(widget.note.copyWith(
                    isArchived: false,
                  )));
                } else {
                  // Archive from Home
                  context.read<NoteBloc>().add(UpdateNoteEvent(widget.note.copyWith(
                    isArchived: true,
                    isPinned: false, // Usually archived notes are unpinned
                  )));
                }
              }
            } else {
              // Swipe Left: Negative Actions (Trash / Permanent Delete)
              if (widget.isTrashView) {
                // Permanent Delete
                context.read<NoteBloc>().add(DeleteNoteEvent(widget.note.id));
                context.read<NoteGroupBloc>().add(RemoveNoteFromAllGroupsEvent(widget.note.id));
              } else {
                // Move to Trash
                context.read<NoteBloc>().add(UpdateNoteEvent(widget.note.copyWith(
                  isDeleted: true,
                  isPinned: false,
                )));
              }
            }
            if (widget.onDismissed != null) widget.onDismissed!();
          },
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: widget.onTapOverride ?? () => navigateTo(toPage: NotePage(note: widget.note)),
            child: cardContent,
          ),
        ),
      ),
    );
  }

  Widget _buildDismissBackground({
    required Color color,
    required IconData icon,
    required Alignment alignment,
    required Color onColor,
  }) {
    return Container(
      margin: const EdgeInsets.all(3),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Align(
        alignment: alignment,
        child: Icon(icon, color: onColor),
      ),
    );
  }
}
