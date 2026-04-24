import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/note_group.dart';
import '../bloc/note_bloc.dart';
import '../bloc/note_event.dart';
import '../bloc/note_state.dart';
import '../bloc/note_group_bloc.dart';
import '../bloc/note_group_event.dart';
import '../bloc/note_group_state.dart';
import '../../../../widgets/home_grid_view.dart';
import 'note_page.dart';
import '../../../../helpers/helper_methods.dart';

class GroupDetailsPage extends StatefulWidget {
  final NoteGroupEntity group;

  const GroupDetailsPage({super.key, required this.group});

  @override
  State<GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Local set to track dismissed note IDs to fix the Dismissible error
  final Set<String> _dismissedNoteIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return BlocBuilder<NoteGroupBloc, NoteGroupState>(
      builder: (context, groupState) {
        // Always get the latest group data from the bloc state
        NoteGroupEntity currentGroup = widget.group;
        if (groupState is NoteGroupLoaded) {
          currentGroup = groupState.groups.cast<NoteGroupEntity>().firstWhere(
                (g) => g.id == widget.group.id,
                orElse: () => widget.group,
              );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(currentGroup.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_rounded),
                onPressed: () =>
                    _showEditGroupNameDialog(context, currentGroup),
              ),
              IconButton(
                icon: const Icon(Icons.delete_rounded),
                onPressed: () => _showDeleteGroupDialog(context, currentGroup),
              ),
            ],
          ),
          body: Column(
            children: [
              _buildSearchHeader(color, currentGroup),
              _buildRemoveDropZone(color, currentGroup),
              Expanded(
                child: BlocListener<NoteBloc, NoteState>(
                  listener: (context, state) {
                    if (state is NoteLoaded) {
                      // Clear local filters when the data source updates (e.g. after a restore or delete)
                      setState(() {
                        _dismissedNoteIds.clear();
                      });
                    }
                  },
                  child: BlocBuilder<NoteBloc, NoteState>(
                    builder: (context, noteState) {
                      if (noteState is NoteLoaded) {
                        var notes = noteState.notes
                            .where((n) => currentGroup.noteIds.contains(n.id))
                            .where((n) => !n.isArchived && !n.isDeleted)
                            .where((n) => !_dismissedNoteIds.contains(n.id))
                            .toList();

                        if (_searchQuery.isNotEmpty) {
                          notes = notes.where((note) {
                            final titleMatch =
                                note.title.toLowerCase().contains(_searchQuery);
                            final contentMatch = note.blocks.any((block) {
                              return block.text
                                      ?.toLowerCase()
                                      .contains(_searchQuery) ??
                                  false;
                            });
                            return titleMatch || contentMatch;
                          }).toList();
                        }

                        if (notes.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.notes_rounded,
                                    size: 48,
                                    color: color.outline.withAlpha(100)),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isEmpty
                                      ? 'No notes in this group'
                                      : 'No matches found in group',
                                  style: TextStyle(color: color.outline),
                                ),
                              ],
                            ),
                          );
                        }

                        return HomeGridView(
                          notes: notes,
                          onNoteTap: (note) {
                            final noteBloc = context.read<NoteBloc>();
                            Navigator.of(context)
                                .push(MaterialPageRoute(
                              builder: (context) => NotePage(note: note),
                            ))
                                .then((_) {
                              noteBloc.add(GetNotesEvent());
                            });
                          },
                          onRemoveFromGroup: (note) =>
                              _removeNoteFromGroup(context, currentGroup, note),
                          onNoteDismissed: (note) {
                            setState(() {
                              _dismissedNoteIds.add(note.id);
                            });
                          },
                        );
                      }
                      return const Center(child: CircularProgressIndicator());
                    },
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _createNewNote(context, currentGroup),
            backgroundColor: color.primary,
            foregroundColor: color.onPrimary,
            elevation: 4,
            child: const Icon(Icons.add_rounded),
          ),
        );
      },
    );
  }

  Widget _buildRemoveDropZone(ColorScheme color, NoteGroupEntity currentGroup) {
    return DragTarget<NoteEntity>(
      onWillAcceptWithDetails: (details) =>
          currentGroup.noteIds.contains(details.data.id),
      onAcceptWithDetails: (details) =>
          _removeNoteFromGroup(context, currentGroup, details.data),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          height: isHovering ? 60 : 0,
          decoration: BoxDecoration(
            color: color.errorContainer.withAlpha(isHovering ? 150 : 0),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isHovering ? color.error : Colors.transparent,
              width: 2,
            ),
          ),
          child: isHovering
              ? Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.remove_circle_rounded, color: color.error),
                      const SizedBox(width: 8),
                      Text('Drop here to remove from group',
                          style: TextStyle(
                              color: color.error, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }

  void _removeNoteFromGroup(
      BuildContext context, NoteGroupEntity currentGroup, NoteEntity note) {
    final groupBloc = context.read<NoteGroupBloc>();
    List<String> newNoteIds = List.from(currentGroup.noteIds)..remove(note.id);
    groupBloc.add(UpdateGroupEvent(currentGroup.copyWith(noteIds: newNoteIds)));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Note removed from ${currentGroup.name}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Widget _buildSearchHeader(ColorScheme color, NoteGroupEntity currentGroup) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: color.surfaceContainerHighest.withAlpha(100),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: color.primary.withAlpha(50)),
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search in ${currentGroup.name}...',
                prefixIcon: Icon(Icons.search_rounded, color: color.primary),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                  _dismissedNoteIds.clear(); // Reset filter when searching
                });
              },
            ),
          ),
        ),
      ),
    );
  }

  void _createNewNote(BuildContext context, NoteGroupEntity currentGroup) {
    final newNote = NoteEntity(
      id: uuid.generate(),
      title: '',
      tags: const [],
      lastModified: DateTime.now(),
      blocks: const [],
    );
    final noteBloc = context.read<NoteBloc>();
    final groupBloc = context.read<NoteGroupBloc>();

    Navigator.of(context)
        .push(MaterialPageRoute(
      builder: (context) => NotePage(note: newNote),
    ))
        .then((_) {
      if (!currentGroup.noteIds.contains(newNote.id)) {
        List<String> newNoteIds = List.from(currentGroup.noteIds)
          ..add(newNote.id);
        groupBloc
            .add(UpdateGroupEvent(currentGroup.copyWith(noteIds: newNoteIds)));
      }
      noteBloc.add(GetNotesEvent());
    });
  }

  void _showEditGroupNameDialog(
      BuildContext context, NoteGroupEntity currentGroup) {
    final color = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: currentGroup.name);
    final groupBloc = context.read<NoteGroupBloc>();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text('Rename Group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Group Name',
            filled: true,
            fillColor: color.surfaceContainerHighest.withAlpha(100),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                groupBloc.add(UpdateGroupEvent(
                  currentGroup.copyWith(name: controller.text),
                ));
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: color.primary,
              foregroundColor: color.onPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteGroupDialog(
      BuildContext context, NoteGroupEntity currentGroup) {
    final groupBloc = context.read<NoteGroupBloc>();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text('Delete Group?'),
        content: const Text(
            'This will only delete the group container, not the notes inside it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              groupBloc.add(DeleteGroupEvent(currentGroup.id));
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Delete',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
