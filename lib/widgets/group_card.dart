import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../constants/themes.dart';
import '../features/notes/domain/entities/note.dart';
import '../features/notes/domain/entities/note_group.dart';
import '../features/notes/presentation/bloc/note_bloc.dart';
import '../features/notes/presentation/bloc/note_group_bloc.dart';
import '../features/notes/presentation/bloc/note_group_event.dart';
import '../features/notes/presentation/bloc/note_state.dart';

/// A group, drawn like a folder listing in a terminal:
///
///     coding/          3
///     ├─ python basics
///     ├─ flutter tips
///     └─ +1 more
///
/// Drop a note on it to add the note to the group.
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
            final shown = notes.take(3).toList();
            final extra = notes.length - shown.length;

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
                        const SizedBox(height: 8),
                        if (hovering)
                          Text('drop to move here',
                              style: monoStyle(context,
                                  size: 11, color: color.primary))
                        else if (notes.isEmpty)
                          Text('└─ empty',
                              style: monoStyle(context,
                                  size: 11, color: tokens.subtle))
                        else ...[
                          for (var i = 0; i < shown.length; i++)
                            Text(
                              '${i == shown.length - 1 && extra == 0 ? '└─' : '├─'} ${shown[i].title.trim().isEmpty ? 'untitled' : shown[i].title.trim()}',
                              style: monoStyle(context,
                                  size: 11, color: tokens.subtle),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (extra > 0)
                            Text('└─ +$extra more',
                                style: monoStyle(context,
                                    size: 11, color: tokens.subtle)),
                        ],
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
