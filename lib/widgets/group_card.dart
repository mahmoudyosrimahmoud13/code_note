import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../constants/themes.dart';
import '../core/util/markdown_preview.dart';
import '../features/notes/domain/entities/block.dart';
import '../features/notes/domain/entities/note.dart';
import '../features/notes/domain/entities/note_group.dart';
import '../features/notes/presentation/bloc/note_bloc.dart';
import '../features/notes/presentation/bloc/note_group_bloc.dart';
import '../features/notes/presentation/bloc/note_group_event.dart';
import '../features/notes/presentation/bloc/note_state.dart';

/// A folder card: its name and count, then mini previews of the notes
/// inside (image thumbnails, code, or text) so you can see what's there
/// without opening it. Drop a note on it to move the note in.
class GroupCard extends StatelessWidget {
  final NoteGroupEntity group;
  final VoidCallback onTap;

  const GroupCard({super.key, required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;

    return BlocSelector<NoteBloc, NoteState, List<NoteEntity>>(
      selector: (state) => state is NoteLoaded
          ? state.notes
              .where((n) =>
                  group.noteIds.contains(n.id) && !n.isArchived && !n.isTrashed)
              .toList()
          : const [],
      builder: (context, notes) {
        return DragTarget<NoteEntity>(
          onWillAcceptWithDetails: (d) => !group.noteIds.contains(d.data.id),
          onAcceptWithDetails: (d) {
            HapticFeedback.mediumImpact();
            context.read<NoteGroupBloc>().add(UpdateGroupEvent(
                group.copyWith(noteIds: [...group.noteIds, d.data.id])));
            ScaffoldMessenger.of(context)
              ..removeCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text('Moved to ${group.name}/')));
          },
          builder: (context, candidates, _) {
            final hovering = candidates.isNotEmpty;
            // More than 4 notes: show 3 previews and a "+N" tile.
            final extra = notes.length > 4 ? notes.length - 3 : 0;

            return Material(
              color: hovering ? color.primaryContainer : color.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppBrand.radius),
                side: BorderSide(
                  color: hovering
                      ? color.primary
                      : color.outlineVariant.withAlpha(160),
                  width: hovering ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Semantics(
                  label: 'Group ${group.name}, ${notes.length} notes',
                  button: true,
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              hovering
                                  ? Icons.drive_file_move_rounded
                                  : Icons.folder_rounded,
                              size: 18,
                              color: color.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${group.name}/',
                                style: monoStyle(context,
                                    size: 13, weight: FontWeight.w700),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text('${notes.length}',
                                style: monoStyle(context,
                                    size: 12, color: tokens.subtle)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: hovering
                              ? Center(
                                  child: Text('drop to move here',
                                      style: monoStyle(context,
                                          size: 12, color: color.primary)),
                                )
                              : notes.isEmpty
                                  ? Center(
                                      child: Text('empty folder',
                                          style: monoStyle(context,
                                              size: 11, color: tokens.subtle)),
                                    )
                                  // Up to 4 mini previews of what's inside.
                                  : GridView.count(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 6,
                                      crossAxisSpacing: 6,
                                      childAspectRatio: 1.35,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      padding: EdgeInsets.zero,
                                      children: [
                                        for (final n in notes.take(extra > 0 ? 3 : 4))
                                          _MiniNotePreview(note: n),
                                        if (extra > 0)
                                          _MoreTile(count: notes.length - 3),
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

/// A tiny version of a note: its first image, else its first code lines,
/// else its title and first text.
class _MiniNotePreview extends StatelessWidget {
  const _MiniNotePreview({required this.note});
  final NoteEntity note;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final title = note.title.trim().isEmpty ? 'untitled' : note.title.trim();

    final image = note.blocks
        .whereType<ImageBlockEntity>()
        .map((b) => b.imagePath)
        .firstWhere((p) => p != null && p.isNotEmpty, orElse: () => null);
    if (image != null) {
      final provider = kIsWeb || image.startsWith('http')
          ? NetworkImage(image) as ImageProvider
          : FileImage(File(image));
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: ResizeImage(provider, width: 240),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: color.surfaceContainer),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(5, 8, 5, 3),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(context, size: 9, color: Colors.white)),
              ),
            ),
          ],
        ),
      );
    }

    // The ★ primary block if the note has one, otherwise the first code.
    CodeBlockEntity? code;
    for (final b in note.blocks) {
      if (b is CodeBlockEntity && (b.text ?? '').trim().isNotEmpty) {
        if (b.runRole == RunRole.main) {
          code = b;
          break;
        }
        code ??= b;
      }
    }
    if (code != null) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: tokens.codeBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(context, size: 9, weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Expanded(
              child: Text(
                code.text!.trim(),
                overflow: TextOverflow.fade,
                softWrap: false,
                style: monoStyle(context, size: 7.5, color: tokens.success)
                    .copyWith(height: 1.35),
              ),
            ),
          ],
        ),
      );
    }

    BlockEntity? textBlock;
    for (final b in note.blocks) {
      if (b is! ImageBlockEntity && (b.text ?? '').trim().isNotEmpty) {
        textBlock = b;
        break;
      }
    }
    final text = (textBlock?.text ?? '').trim();
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(fontWeight: FontWeight.w700, fontSize: 9.5)),
          const SizedBox(height: 2),
          Expanded(
            child: textBlock is MarkdownBlockEntity
                ? ClipRect(child: MarkdownPreviewText(text, maxLines: 6, fontSize: 8))
                : Text(
                    text,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                        fontSize: 8, height: 1.3, color: color.onSurfaceVariant),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('+$count',
          style: monoStyle(context,
              size: 14, weight: FontWeight.w700, color: context.tokens.subtle)),
    );
  }
}
