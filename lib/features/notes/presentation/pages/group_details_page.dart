import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/note_group.dart';
import '../bloc/note_bloc.dart';
import '../bloc/note_state.dart';
import '../bloc/note_group_bloc.dart';
import '../bloc/note_group_event.dart';
import '../bloc/note_group_state.dart';
import '../../../../widgets/home_grid_view.dart';
import 'note_page.dart';
import 'web_preview_page.dart';
import '../../../backup/codenote_files.dart';
import '../../../runner/run_manager.dart';
import '../../../runner/sandbox.dart';
import '../../../runner/run_order_sheet.dart';
import '../../../runner/running_indicator.dart';
import '../../../../helpers/helper_methods.dart';
import '../../../../constants/themes.dart';
import '../../../../widgets/brand.dart';

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

        return ListenableBuilder(
          listenable: RunManager.instance,
          builder: (context, _) => Scaffold(
          appBar: AppBar(
            bottom: RunManager.instance.sequenceRunning(currentGroup.id)
                ? _FolderRunStatus(folderId: currentGroup.id)
                : null,
            title: Text('~/${currentGroup.name}/',
                style: monoStyle(context, size: 17, weight: FontWeight.w700)),
            actions: [
              _RunFolderButton(group: currentGroup),
              IconButton(
                tooltip: 'Share folder as a .codenote file',
                icon: const Icon(Icons.ios_share_rounded),
                onPressed: () => CodenoteFiles.shareFolder(context, currentGroup),
              ),
              IconButton(
                tooltip: 'Rename group',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () =>
                    _showEditGroupNameDialog(context, currentGroup),
              ),
              IconButton(
                tooltip: 'Delete group',
                icon: const Icon(Icons.delete_outline_rounded),
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
                            .where((n) => !n.isArchived && !n.isTrashed)
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
                          return _searchQuery.isEmpty
                              ? TerminalEmptyState(
                                  command: 'ls ~/${currentGroup.name}/',
                                  output: 'total 0',
                                  hint:
                                      'Tap + to write a note here, or drag a note onto this folder from the home screen.',
                                )
                              : TerminalEmptyState(
                                  command:
                                      'grep -r "$_searchQuery" ~/${currentGroup.name}/',
                                  output: '0 matches',
                                );
                        }

                        return HomeGridView(
                          notes: notes,
                          onNoteTap: (note) {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) => NotePage(note: note),
                            ));
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
            tooltip: 'New note in this group',
            onPressed: () => _createNewNote(context, currentGroup),
            child: const Icon(Icons.add_rounded),
          ),
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _searchController,
            style: monoStyle(context, size: 14),
            decoration: InputDecoration(
              hintText: 'grep ${currentGroup.name}/…',
              hintStyle: monoStyle(context, size: 14, color: context.tokens.subtle),
              prefixIcon: Icon(Icons.search_rounded, color: color.primary),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value.toLowerCase();
                _dismissedNoteIds.clear();
              });
            },
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
    // The editor adds the note to this folder when it's first saved.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => NotePage(note: newNote, groupId: currentGroup.id),
    ));
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
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete group'),
          ),
        ],
      ),
    );
  }
}


/// ▶ Runs the folder as a sequence (see the Run order sheet), then opens
/// its web pages. ≡ opens the Run order sheet.
class _RunFolderButton extends StatelessWidget {
  const _RunFolderButton({required this.group});
  final NoteGroupEntity group;

  List<NoteEntity> _notes(BuildContext context) {
    final st = context.read<NoteBloc>().state;
    if (st is! NoteLoaded) return const [];
    return st.notes.where((n) => group.noteIds.contains(n.id) && !n.isTrashed).toList();
  }

  Future<void> _run(BuildContext context) async {
    final notes = _notes(context);
    final pages = notes.where((n) => WebPreview.canPreview(n.blocks)).toList();
    final spaceKey = Sandbox.keyFor(noteId: '', folderId: group.id);
    final messenger = ScaffoldMessenger.of(context);
    if (RunManager.runnableNotes(group, notes).isEmpty && pages.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Nothing to run here. Add Python, Bash, JavaScript, Dart or web code to a note.'),
          persist: false));
      return;
    }
    final problem = await RunManager.instance.runFolder(group, notes, spaceKey);
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem), persist: false));
      return;
    }
    if (pages.isEmpty || !context.mounted) return;
    // Give the primary server a moment to start before the pages call it.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!context.mounted) return;
    final phone = Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;
    for (final page in phone ? pages.take(1) : pages) {
      if (!context.mounted) return;
      await WebPreview.open(context, page, spaceKey: spaceKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RunManager.instance,
      builder: (context, _) {
        final notes = _notes(context);
        final running = RunManager.instance.folderRunning(notes) || RunManager.instance.sequenceRunning(group.id);
        return Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Run order',
            icon: const Icon(Icons.low_priority_rounded),
            onPressed: () => showRunOrderSheet(context, group, notes),
          ),
          IconButton(
            tooltip: running ? 'Running · tap to stop everything in this folder' : 'Run folder (in order, then web pages)',
            icon: RunButtonIcon(running: running, size: 22),
            onPressed: () => running ? RunManager.instance.stopFolder(group.id, notes) : _run(context),
          ),
        ]);
      },
    );
  }
}

/// "step 2 of 4: Backend" under the folder title while a run starts.
class _FolderRunStatus extends StatelessWidget implements PreferredSizeWidget {
  const _FolderRunStatus({required this.folderId});
  final String folderId;

  @override
  Size get preferredSize => const Size.fromHeight(24);

  @override
  Widget build(BuildContext context) {
    final status = RunManager.instance.folderStatus[folderId] ?? '';
    return Container(
      height: 24,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: context.tokens.success)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(status,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: monoStyle(context, size: 12, color: context.tokens.success)),
        ),
      ]),
    );
  }
}
