import 'dart:io';

import 'package:code_note/helpers/helper_methods.dart';
import 'package:code_note/features/notes/domain/entities/note.dart';
import 'package:code_note/features/notes/domain/entities/block.dart';
import 'package:code_note/features/notes/presentation/pages/note_page.dart';
import 'package:code_note/features/notes/presentation/bloc/note_bloc.dart';
import 'package:code_note/features/notes/presentation/bloc/note_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

class NoteCard extends StatelessWidget {
  final NoteEntity note;
  final bool isTrashView;
  late final DateTime lastModified;
  File? image;
  String? title;
  late final String body;

  NoteCard({super.key, required this.note, this.isTrashView = false}) {
    lastModified = note.lastModified;
    title = note.title;
    
    // Find first text block for body
    body = note.blocks
        .whereType<NoteBlockEntity>()
        .map((b) => b.text ?? '')
        .firstWhere((t) => t.isNotEmpty, orElse: () => 'empty note.');

    // Find first image block for preview
    final imageBlock = note.blocks
        .whereType<ImageBlockEntity>()
        .firstOrNull;
    
    if (imageBlock?.imagePath != null) {
      image = File(imageBlock!.imagePath!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final textTheme = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey(note.id),
      secondaryBackground: Container(
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: color.secondary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Align(
          alignment: Alignment.centerRight,
          child: Icon(Icons.archive, color: color.onSecondary),
        ),
      ),
      background: Container(
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: color.error,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Icon(Icons.delete, color: color.onError),
        ),
      ),
      onDismissed: (direction) {
        if (isTrashView) {
          if (direction == DismissDirection.endToStart) {
            // Restore from Trash
            context.read<NoteBloc>().add(UpdateNoteEvent(note.copyWith(isDeleted: false)));
          } else {
            // Hard delete
            context.read<NoteBloc>().add(DeleteNoteEvent(note.id));
          }
        } else {
          if (direction == DismissDirection.endToStart) {
            context.read<NoteBloc>().add(UpdateNoteEvent(note.copyWith(isArchived: true)));
          } else {
            // Move to Trash instead of hard delete
            context.read<NoteBloc>().add(UpdateNoteEvent(note.copyWith(isDeleted: true, isPinned: false)));
          }
        }
      },
      child: InkWell(
        onTap: () => navigateTo(toPage: NotePage(note: note)),
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: color.onSurface.withAlpha(30),
            borderRadius: BorderRadius.circular(20),
          ),
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (image != null)
                Container(
                  width: double.infinity,
                  height: size.height * 0.2,
                  decoration: BoxDecoration(
                      color: color.onSurface.withAlpha(30),
                      borderRadius: BorderRadius.circular(20),
                      image: DecorationImage(
                        image: FileImage(image!),
                        fit: BoxFit.cover,
                      )),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
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
                              style: textTheme.titleMedium!.copyWith(
                                color: color.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        IconButton(
                          icon: Icon(
                            note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                            size: 18,
                            color: note.isPinned ? color.primary : color.secondary,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            context.read<NoteBloc>().add(
                              UpdateNoteEvent(note.copyWith(isPinned: !note.isPinned)),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: textTheme.bodySmall!.copyWith(color: color.secondary),
                      maxLines: 10,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat.yMMMd().format(lastModified),
                      style: textTheme.labelSmall!.copyWith(color: color.secondary.withAlpha(150)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
