import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../features/notes/domain/entities/note.dart';
import '../../features/notes/domain/entities/note_group.dart';
import '../../features/notes/domain/entities/block.dart';
import '../../features/notes/presentation/bloc/note_bloc.dart';
import '../../features/notes/presentation/bloc/note_state.dart';
import '../../features/notes/presentation/bloc/note_group_bloc.dart';
import '../../features/notes/presentation/bloc/note_group_event.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:code_note/widgets/animated_icons.dart';

class GroupCard extends StatefulWidget {
  final NoteGroupEntity group;
  final VoidCallback onTap;

  const GroupCard({
    super.key,
    required this.group,
    required this.onTap,
  });

  @override
  State<GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<GroupCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return BlocBuilder<NoteBloc, NoteState>(
      builder: (context, state) {
        List<NoteEntity> groupNotes = [];
        if (state is NoteLoaded) {
          groupNotes = state.notes
              .where((n) => widget.group.noteIds.contains(n.id))
              .where((n) => !n.isArchived && !n.isDeleted)
              .toList();
        }

        return DragTarget<NoteEntity>(
          onWillAcceptWithDetails: (details) => !widget.group.noteIds.contains(details.data.id),
          onAcceptWithDetails: (details) {
            final note = details.data;
            List<String> newNoteIds = List.from(widget.group.noteIds)..add(note.id);
            context.read<NoteGroupBloc>().add(UpdateGroupEvent(
              widget.group.copyWith(noteIds: newNoteIds),
            ));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Note added to ${widget.group.name}'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: color.primary,
                duration: const Duration(seconds: 1),
              ),
            );
          },
          builder: (context, candidateData, rejectedData) {
            final isHovering = candidateData.isNotEmpty;
            
            return MouseRegion(
              onEnter: (_) => _controller.forward(),
              onExit: (_) => _controller.reverse(),
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: BorderRadius.circular(28),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isHovering 
                        ? color.primaryContainer.withAlpha(150) 
                        : color.surfaceContainerHighest.withAlpha(60),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: isHovering 
                          ? color.primary 
                          : color.outlineVariant.withAlpha(100),
                        width: isHovering ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isHovering 
                            ? color.primary.withAlpha(50) 
                            : Colors.black.withAlpha(10),
                          blurRadius: isHovering ? 15 : 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: color.surface.withAlpha(150),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                              itemCount: groupNotes.length > 4 ? 4 : groupNotes.length,
                              itemBuilder: (context, index) {
                                final note = groupNotes[index];
                                return _NoteMiniPreview(note: note);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.group.name,
                                      style: textTheme.titleSmall!.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: color.onSurface,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${groupNotes.length} notes',
                                      style: textTheme.labelSmall!.copyWith(
                                        color: color.outline,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PulsingIcon(
                                icon: Icons.folder_open_rounded,
                                size: 16,
                                color: color.primary.withAlpha(150),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _NoteMiniPreview extends StatelessWidget {
  final NoteEntity note;

  const _NoteMiniPreview({required this.note});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    
    // Try to find an image first
    final imageBlock = note.blocks.whereType<ImageBlockEntity>().firstOrNull;
    if (imageBlock?.imagePath != null) {
      return Container(
        decoration: BoxDecoration(
          color: color.surface,
          borderRadius: BorderRadius.circular(8),
          image: DecorationImage(
            image: kIsWeb 
              ? NetworkImage(imageBlock!.imagePath!) as ImageProvider
              : FileImage(File(imageBlock!.imagePath!)),
            fit: BoxFit.cover,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 4,
            )
          ],
        ),
      );
    }

    // Otherwise show text snippet
    final textBlock = note.blocks.whereType<NoteBlockEntity>().firstOrNull;
    final text = (note.title.isNotEmpty ? note.title : textBlock?.text) ?? '';

    return Container(
      decoration: BoxDecoration(
        color: color.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.outlineVariant.withAlpha(80)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 4,
          )
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (text.isNotEmpty)
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 6, height: 1.3),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(height: 3, width: 20, decoration: BoxDecoration(color: color.primary.withAlpha(120), borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 4),
                Container(height: 3, width: 14, decoration: BoxDecoration(color: color.outlineVariant.withAlpha(150), borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 4),
                Container(height: 3, width: 18, decoration: BoxDecoration(color: color.outlineVariant.withAlpha(100), borderRadius: BorderRadius.circular(2))),
              ],
            ),
        ],
      ),
    );
  }
}
