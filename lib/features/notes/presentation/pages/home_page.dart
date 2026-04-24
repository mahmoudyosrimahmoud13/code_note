import 'package:code_note/core/util/platform_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:code_note/features/notes/domain/entities/note.dart';
import 'package:code_note/features/notes/domain/entities/note_group.dart';
import 'package:code_note/features/notes/presentation/bloc/note_bloc.dart';
import 'package:code_note/features/notes/presentation/bloc/note_event.dart';
import 'package:code_note/features/notes/presentation/bloc/note_state.dart';
import 'package:code_note/features/notes/presentation/bloc/note_group_bloc.dart';
import 'package:code_note/features/notes/presentation/bloc/note_group_event.dart';
import 'package:code_note/features/notes/presentation/bloc/note_group_state.dart';
import 'package:code_note/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:code_note/features/settings/presentation/bloc/settings_event.dart';
import 'package:code_note/features/settings/presentation/bloc/settings_state.dart';
import 'package:code_note/features/notes/presentation/pages/note_page.dart';
import 'package:code_note/features/notes/presentation/pages/group_details_page.dart';
import 'package:code_note/widgets/custom_icon_button.dart';
import 'package:code_note/widgets/home_grid_view.dart';
import 'package:code_note/widgets/home_navigation_bar.dart';
import 'package:code_note/widgets/user_home_padge.dart';
import 'package:code_note/widgets/group_card.dart';
import 'package:code_note/helpers/helper_methods.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  
  // Local set to track dismissed note IDs to fix the Dismissible error
  final Set<String> _dismissedNoteIds = {};

  @override
  void initState() {
    super.initState();
    final settingsBloc = context.read<SettingsBloc>();
    if (settingsBloc.state is SettingsLoaded) {
      _selectedIndex = (settingsBloc.state as SettingsLoaded).settings.lastSelectedIndex;
    }
  }

  void _addNote(BuildContext context) {
    final note = NoteEntity(
      id: uuid.generate(),
      title: '',
      tags: const [],
      lastModified: DateTime.now(),
      blocks: const [],
    );
    final noteBloc = context.read<NoteBloc>();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => NotePage(note: note),
    )).then((_) {
      noteBloc.add(GetNotesEvent());
    });
  }

  void _createGroup(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Group Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                final group = NoteGroupEntity(
                  id: uuid.generate(),
                  name: controller.text,
                  noteIds: const [],
                  lastModified: DateTime.now(),
                );
                context.read<NoteGroupBloc>().add(AddGroupEvent(group));
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, ColorScheme color) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.primary.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: color.primary),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 0.5,
                color: color.onSurface.withAlpha(220),
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, size: 16, color: color.outline.withAlpha(100)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                    _isSearching = false;
                    _searchController.clear();
                    _dismissedNoteIds.clear(); // Clear local dismiss cache
                  });
                  // Persist the last selected index
                  final settingsBloc = context.read<SettingsBloc>();
                  if (settingsBloc.state is SettingsLoaded) {
                    final currentSettings = (settingsBloc.state as SettingsLoaded).settings;
                    settingsBloc.add(UpdateSettingsEvent(
                      currentSettings.copyWith(lastSelectedIndex: index),
                    ));
                  }
                },
                labelType: NavigationRailLabelType.selected,
                backgroundColor: color.surface.withAlpha(100),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.note_outlined),
                    selectedIcon: Icon(Icons.note),
                    label: Text('All Notes'),
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
            Expanded(
              child: BlocBuilder<NoteBloc, NoteState>(
                builder: (context, noteState) {
                  return Column(
                    children: [
                      _buildHeader(color),
                      if (noteState is NoteLoaded) _buildTagCloud(noteState.notes, color),
                      if (_isSearching && _searchController.text.isNotEmpty && noteState is NoteLoaded)
                        _buildSearchSuggestions(noteState.notes, color),
                      Expanded(
                        child: BlocBuilder<NoteGroupBloc, NoteGroupState>(
                          builder: (context, groupState) {
                            if (noteState is NoteInitial || groupState is NoteGroupInitial) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            
                            if (noteState is NoteLoaded && groupState is NoteGroupLoaded) {
                              // Filter out local dismissed notes to prevent the tree error
                              List<NoteEntity> notes = noteState.notes
                                  .where((n) => !_dismissedNoteIds.contains(n.id))
                                  .toList();
                              List<NoteGroupEntity> groups = groupState.groups;

                              if (!_isSearching) {
                                if (_selectedIndex == 3) {
                                  // Archive View
                                  notes = notes.where((n) => n.isArchived && !n.isDeleted).toList();
                                  groups = [];
                                } else if (_selectedIndex == 4) {
                                  // Trash View
                                  notes = notes.where((n) => n.isDeleted).toList();
                                  groups = [];
                                } else if (_selectedIndex == 1) {
                                  // Reminders View
                                  notes = notes.where((n) => n.reminder != null && !n.isArchived && !n.isDeleted).toList();
                                  groups = [];
                                } else {
                                  // Notes View
                                  notes = notes.where((n) => !n.isArchived && !n.isDeleted).toList();
                                  final notesInGroups = groups.expand((g) => g.noteIds).toSet();
                                  notes = notes.where((n) => !notesInGroups.contains(n.id)).toList();
                                }
                              }

                              if (notes.isEmpty && groups.isEmpty) {
                                return _buildEmptyState(color);
                              }

                              final pinnedNotes = notes.where((n) => n.isPinned).toList();
                              final normalNotes = notes.where((n) => !n.isPinned).toList();

                              return CustomScrollView(
                                physics: const BouncingScrollPhysics(),
                                slivers: [
                                  if (groups.isNotEmpty && !_isSearching && _selectedIndex == 0) ...[
                                    _buildSectionTitle('Groups', Icons.folder_copy_rounded, color),
                                    SliverPadding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                      sliver: SliverGrid(
                                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                          maxCrossAxisExtent: 200.0,
                                          mainAxisSpacing: 12.0,
                                          crossAxisSpacing: 12.0,
                                          childAspectRatio: 0.9,
                                        ),
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) {
                                            return Hero(
                                              tag: 'group_${groups[index].id}',
                                              child: GroupCard(
                                                group: groups[index],
                                                onTap: () {
                                                  Navigator.push(context, MaterialPageRoute(
                                                    builder: (context) => GroupDetailsPage(group: groups[index]),
                                                  ));
                                                },
                                              ),
                                            );
                                          },
                                          childCount: groups.length,
                                        ),
                                      ),
                                    ),
                                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                                  ],
                                  if (pinnedNotes.isNotEmpty && !_isSearching && _selectedIndex == 0) ...[
                                    _buildSectionTitle('Pinned', Icons.push_pin_rounded, color),
                                    SliverPadding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                      sliver: SliverToBoxAdapter(
                                        child: HomeGridView(
                                          notes: pinnedNotes,
                                          isShrinkWrap: true,
                                        ),
                                      ),
                                    ),
                                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                                  ],
                                  if (normalNotes.isNotEmpty || groups.isNotEmpty || _isSearching) ...[
                                    if (!_isSearching && _selectedIndex == 0 && pinnedNotes.isNotEmpty)
                                      _buildSectionTitle('Notes', Icons.notes_rounded, color),
                                    SliverPadding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                      sliver: SliverToBoxAdapter(
                                        child: HomeGridView(
                                          notes: _isSearching ? notes : normalNotes,
                                          isTrashView: _selectedIndex == 2 && !_isSearching,
                                          isShrinkWrap: true,
                                          onNoteDismissed: (note) {
                                            setState(() {
                                              _dismissedNoteIds.add(note.id);
                                            });
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                                ],
                              );
                            }
                            
                            return const Center(child: CircularProgressIndicator());
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: !PlatformHelper.isDesktopOrWeb
          ? NavBar(
              selectedIndex: _selectedIndex,
              onIndexChanged: (index) {
                setState(() {
                  _selectedIndex = index;
                  _isSearching = false;
                  _searchController.clear();
                  _dismissedNoteIds.clear();
                });
                
                // Persist the last selected index
                final settingsBloc = context.read<SettingsBloc>();
                if (settingsBloc.state is SettingsLoaded) {
                  final currentSettings = (settingsBloc.state as SettingsLoaded).settings;
                  settingsBloc.add(UpdateSettingsEvent(
                    currentSettings.copyWith(lastSelectedIndex: index),
                  ));
                }
              },
              addNote: () => _addNote(context),
            )
          : null,
      floatingActionButton: PlatformHelper.isDesktopOrWeb 
          ? FloatingActionButton(
              onPressed: () => _addNote(context),
              backgroundColor: color.primary,
              foregroundColor: color.onPrimary,
              elevation: 4,
              child: const Icon(Icons.add_rounded),
            )
          : null,
    );
  }

  Widget _buildHeader(ColorScheme color) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (!_isSearching)
            const Expanded(child: UserHomePadge())
          else
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: color.surfaceContainerHighest.withAlpha(100),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: color.primary.withAlpha(50)),
                    ),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search in notes...',
                        prefixIcon: Icon(Icons.search, color: color.primary),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() {
                              _isSearching = false;
                              _searchController.clear();
                              context.read<NoteBloc>().add(GetNotesEvent());
                            });
                          },
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: (query) {
                        context.read<NoteBloc>().add(SearchNotesEvent(query));
                      },
                    ),
                  ),
                ),
              ),
            ),
          if (!_isSearching)
            Row(
              children: [
                _buildAnimatedHeaderButton(
                  icon: Icons.create_new_folder_rounded,
                  onPressed: () => _createGroup(context),
                  color: color,
                ),
                const SizedBox(width: 8),
                _buildAnimatedHeaderButton(
                  icon: Icons.search_rounded,
                  onPressed: () {
                    setState(() {
                      _isSearching = true;
                    });
                  },
                  color: color,
                ),
                const SizedBox(width: 8),
                _buildAnimatedHeaderButton(
                  icon: Icons.notifications_rounded,
                  onPressed: () {
                    setState(() {
                      _selectedIndex = 1; // Switch to Reminders view
                      _isSearching = false;
                      _searchController.clear();
                    });
                  },
                  color: color,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildAnimatedHeaderButton({required IconData icon, required VoidCallback onPressed, required ColorScheme color}) {
    return CustomIconButton(
      icon: icon,
      onPressed: onPressed,
    );
  }

  Widget _buildEmptyState(ColorScheme color) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: color.primary.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.note_alt_rounded, size: 64, color: color.primary.withAlpha(150)),
          ),
          const SizedBox(height: 24),
          Text(
            _isSearching ? 'No notes match your search' : 'Your workspace is empty',
            style: TextStyle(
              color: color.onSurface.withAlpha(180),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start by creating your first note!',
            style: TextStyle(color: color.outline, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildTagCloud(List<NoteEntity> notes, ColorScheme color) {
    final allTags = notes.expand((n) => n.tags).toSet().toList();
    if (allTags.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: allTags.length,
        itemBuilder: (context, index) {
          final tag = allTags[index];
          final isSelected = _isSearching && _searchController.text.toLowerCase() == tag.toLowerCase();
          
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ActionChip(
              label: Text('#$tag', style: TextStyle(
                fontSize: 12, 
                color: isSelected ? color.onPrimary : color.primary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              )),
              backgroundColor: isSelected ? color.primary : color.primaryContainer.withAlpha(100),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              side: BorderSide.none,
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _isSearching = true;
                  _searchController.text = tag;
                });
                context.read<NoteBloc>().add(SearchNotesEvent(tag));
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchSuggestions(List<NoteEntity> notes, ColorScheme color) {
    final query = _searchController.text.toLowerCase();
    final matchingTags = notes
        .expand((n) => n.tags)
        .toSet()
        .where((t) => t.toLowerCase().contains(query))
        .take(5)
        .toList();
    
    final matchingTitles = notes
        .where((n) => n.title.toLowerCase().contains(query))
        .map((n) => n.title)
        .take(5)
        .toList();

    if (matchingTags.isEmpty && matchingTitles.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withAlpha(150),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...matchingTags.map((tag) => _buildSuggestionItem(Icons.tag_rounded, tag, color)),
          ...matchingTitles.map((title) => _buildSuggestionItem(Icons.title_rounded, title, color)),
        ],
      ),
    );
  }

  Widget _buildSuggestionItem(IconData icon, String text, ColorScheme color) {
    return InkWell(
      onTap: () {
        setState(() {
          _searchController.text = text;
        });
        context.read<NoteBloc>().add(SearchNotesEvent(text));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color.primary.withAlpha(150)),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}
