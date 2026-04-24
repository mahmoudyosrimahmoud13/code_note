import 'package:code_note/core/util/platform_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../widgets/custom_icon_button.dart';
import '../../../../widgets/home_grid_view.dart';
import '../../../../widgets/home_navigation_bar.dart';
import '../../../../widgets/user_home_padge.dart';
import '../../domain/entities/note.dart';
import '../bloc/note_bloc.dart';
import '../bloc/note_event.dart';
import '../bloc/note_state.dart';
import 'note_page.dart';
import '../../../../helpers/helper_methods.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  void _addNote(BuildContext context) {
    final note = NoteEntity(
      id: uuid.generate(),
      title: '',
      tags: const [],
      lastModified: DateTime.now(),
      blocks: const [],
    );
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => NotePage(note: note),
    )).then((_) {
      if (!mounted) return;
      context.read<NoteBloc>().add(GetNotesEvent());
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (PlatformHelper.isDesktopOrWeb)
              NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                },
                labelType: NavigationRailLabelType.all,
                backgroundColor: color.surface,
                indicatorColor: color.primary.withAlpha(50),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.note_outlined),
                    selectedIcon: Icon(Icons.note),
                    label: Text('Notes'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.notifications_none),
                    selectedIcon: Icon(Icons.notifications),
                    label: Text('Reminders'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.edit_outlined),
                    selectedIcon: Icon(Icons.edit),
                    label: Text('Edit Labels'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.archive_outlined),
                    selectedIcon: Icon(Icons.archive),
                    label: Text('Archive'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.delete_outline),
                    selectedIcon: Icon(Icons.delete),
                    label: Text('Trash'),
                  ),
                ],
              ),
            if (PlatformHelper.isDesktopOrWeb) const VerticalDivider(thickness: 1, width: 1),
            Expanded(
              child: BlocBuilder<NoteBloc, NoteState>(
                builder: (context, state) {
                  if (state is NoteLoaded) {
                    return Stack(
                      children: [
                        Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const UserHomePadge(),
                                  SizedBox(
                                    width: size.width * 0.3,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        CustomIconButton(icon: Icons.search),
                                        const SizedBox(width: 0),
                                        CustomIconButton(icon: Icons.people)
                                      ],
                                    ),
                                  )
                                ],
                              ),
                            ),
                            Expanded(
                              child: Builder(builder: (context) {
                                final List<NoteEntity> filteredNotes;
                                
                                switch (_selectedIndex) {
                                  case 0: // Notes
                                    filteredNotes = state.notes.where((n) => !n.isArchived && !n.isDeleted).toList();
                                    break;
                                  case 3: // Archive
                                    filteredNotes = state.notes.where((n) => n.isArchived && !n.isDeleted).toList();
                                    break;
                                  case 4: // Trash
                                    filteredNotes = state.notes.where((n) => n.isDeleted).toList();
                                    break;
                                  default:
                                    filteredNotes = [];
                                }

                                if (filteredNotes.isEmpty) {
                                  return Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          _selectedIndex == 3 ? Icons.archive : _selectedIndex == 4 ? Icons.delete_outline : Icons.note_outlined,
                                          size: 100,
                                          color: color.secondary.withAlpha(50),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          _selectedIndex == 3 ? 'No archived notes' : _selectedIndex == 4 ? 'Trash is empty' : 'No notes yet',
                                          style: TextStyle(color: color.secondary),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                if (_selectedIndex == 0) {
                                  final pinnedNotes = filteredNotes.where((n) => n.isPinned).toList();
                                  final otherNotes = filteredNotes.where((n) => !n.isPinned).toList();

                                  return SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (pinnedNotes.isNotEmpty) ...[
                                          const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            child: Text('PINNED', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                                          ),
                                          HomeGridView(notes: pinnedNotes, isShrinkWrap: true),
                                          const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            child: Text('OTHERS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                                          ),
                                        ],
                                        HomeGridView(notes: otherNotes, isShrinkWrap: true),
                                      ],
                                    ),
                                  );
                                }

                                return HomeGridView(
                                  notes: filteredNotes,
                                  isTrashView: _selectedIndex == 4,
                                );
                              }),
                            ),
                            const SizedBox(height: 40)
                          ],
                        ),
                        if (!PlatformHelper.isDesktopOrWeb)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: NavBar(
                              addNote: () => _addNote(context),
                            ),
                          ),
                        if (PlatformHelper.isDesktopOrWeb)
                          Positioned(
                            right: 32,
                            bottom: 32,
                            child: FloatingActionButton.extended(
                              onPressed: () => _addNote(context),
                              icon: const Icon(Icons.add),
                              label: const Text('Add Note'),
                            ),
                          ),
                      ],
                    );
                  } else if (state is NoteLoading) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (state is NoteError) {
                    return Center(child: Text(state.message));
                  } else {
                    return const Center(child: Icon(Icons.error));
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
