import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/log_service.dart';
import '../../../../core/services/log_viewer_page.dart';
import '../../../../core/services/sharing_service.dart';
import '../../../../core/util/platform_helper.dart';
import '../../../../helpers/helper_methods.dart';
import '../../../../widgets/custom_icon_button.dart';
import '../../../../widgets/group_card.dart';
import '../../../../widgets/home_grid_view.dart';
import '../../../../widgets/home_navigation_bar.dart';
import '../../../../widgets/user_home_padge.dart';
import '../../../settings/presentation/bloc/settings_bloc.dart';
import '../../../settings/presentation/bloc/settings_event.dart';
import '../../../settings/presentation/bloc/settings_state.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/note_group.dart';
import '../bloc/note_bloc.dart';
import '../bloc/note_event.dart';
import '../bloc/note_group_bloc.dart';
import '../bloc/note_group_event.dart';
import '../bloc/note_group_state.dart';
import '../bloc/note_state.dart';
import 'group_details_page.dart';
import 'note_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  int _versionClickCount = 0;
  DateTime? _lastClickTime;

  final Set<String> _dismissedNoteIds = {};

  @override
  void initState() {
    super.initState();
    final settingsBloc = context.read<SettingsBloc>();
    if (settingsBloc.state is SettingsLoaded) {
      _selectedIndex = (settingsBloc.state as SettingsLoaded).settings.lastSelectedIndex;
    }

    SharingService().init(context);
    LogService().log("HomePage: Initialized in Local-Only mode.");
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

  @override
  void dispose() {
    _searchController.dispose();
    SharingService().dispose();
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
              BlocBuilder<NoteBloc, NoteState>(
                builder: (context, state) {
                  return NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (index) {
                      setState(() {
                        _selectedIndex = index;
                        _isSearching = false;
                        _searchController.clear();
                        _dismissedNoteIds.clear();
                      });
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
                        icon: Icon(Icons.notifications_none_rounded),
                        selectedIcon: Icon(Icons.notifications_rounded),
                        label: Text('Reminders'),
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
                  );
                },
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
                              List<NoteEntity> filteredNotes = noteState.notes.where((n) => !_dismissedNoteIds.contains(n.id)).toList();
                              List<NoteGroupEntity> groups = groupState.groups;

                              if (!_isSearching) {
                                if (_selectedIndex == 3) {
                                  filteredNotes = filteredNotes.where((n) => n.isTrashed).toList();
                                  groups = [];
                                } else if (_selectedIndex == 2) {
                                  filteredNotes = filteredNotes.where((n) => n.isArchived && !n.isTrashed).toList();
                                  groups = [];
                                } else if (_selectedIndex == 1) {
                                  filteredNotes = filteredNotes.where((n) => n.reminder != null && !n.isArchived && !n.isTrashed).toList();
                                  groups = [];
                                } else {
                                  filteredNotes = filteredNotes.where((n) => !n.isArchived && !n.isTrashed).toList();
                                  final notesInGroups = groups.expand((g) => g.noteIds).toSet();
                                  filteredNotes = filteredNotes.where((n) => !notesInGroups.contains(n.id)).toList();
                                }
                              } else {
                                filteredNotes = filteredNotes.where((n) => !n.isTrashed).toList();
                              }

                              filteredNotes.sort((a, b) {
                                if (a.isPinned && !b.isPinned) return -1;
                                if (!a.isPinned && b.isPinned) return 1;
                                return b.lastModified.compareTo(a.lastModified);
                              });

                              if (filteredNotes.isEmpty && groups.isEmpty) {
                                return _buildEmptyState(color);
                              }

                              final pinnedNotes = filteredNotes.where((n) => n.isPinned).toList();
                              final normalNotes = filteredNotes.where((n) => !n.isPinned).toList();

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
                                          (context, index) => Hero(
                                            tag: 'group_${groups[index].id}',
                                            child: GroupCard(
                                              group: groups[index],
                                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                                builder: (context) => GroupDetailsPage(group: groups[index]),
                                              )),
                                            ),
                                          ),
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
                                          onNoteDismissed: (note) => setState(() => _dismissedNoteIds.add(note.id)),
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
                                          notes: _isSearching ? filteredNotes : normalNotes,
                                          isTrashView: _selectedIndex == 3 && !_isSearching,
                                          isShrinkWrap: true,
                                          onNoteDismissed: (note) => setState(() => _dismissedNoteIds.add(note.id)),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                                  SliverToBoxAdapter(
                                    child: GestureDetector(
                                      onTap: () {
                                        final now = DateTime.now();
                                        if (_lastClickTime == null || now.difference(_lastClickTime!) > const Duration(seconds: 2)) {
                                          _versionClickCount = 1;
                                        } else {
                                          _versionClickCount++;
                                        }
                                        _lastClickTime = now;
                                        if (_versionClickCount >= 3) {
                                          _versionClickCount = 0;
                                          HapticFeedback.heavyImpact();
                                          Navigator.push(context, MaterialPageRoute(builder: (context) => const LogViewerPage()));
                                        }
                                      },
                                      child: Center(
                                        child: Text(
                                          'Version 1.2.0 (Open Source)',
                                          style: TextStyle(fontSize: 10, color: color.outline.withAlpha(50)),
                                        ),
                                      ),
                                    ),
                                  ),
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
                final settingsBloc = context.read<SettingsBloc>();
                if (settingsBloc.state is SettingsLoaded) {
                  final currentSettings = (settingsBloc.state as SettingsLoaded).settings;
                  settingsBloc.add(UpdateSettingsEvent(currentSettings.copyWith(lastSelectedIndex: index)));
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
          if (!_isSearching) const Expanded(child: UserHomePadge())
          else Expanded(
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
                      onChanged: (query) => context.read<NoteBloc>().add(SearchNotesEvent(query)),
                    ),
                  ),
                ),
              ),
            ),
          if (!_isSearching) Row(
            children: [
              CustomIconButton(
                icon: Icons.create_new_folder_rounded,
                onPressed: () => _createGroup(context),
              ),
              const SizedBox(width: 8),
              CustomIconButton(
                icon: Icons.search_rounded,
                onPressed: () => setState(() => _isSearching = true),
              ),
            ],
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
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color.onSurface.withAlpha(220))),
            const Spacer(),
            Icon(Icons.chevron_right, size: 16, color: color.outline.withAlpha(100)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme color) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: color.primary.withAlpha(20), shape: BoxShape.circle),
            child: Icon(Icons.note_alt_rounded, size: 64, color: color.primary.withAlpha(150)),
          ),
          const SizedBox(height: 24),
          Text(_isSearching ? 'No notes match your search' : 'Your workspace is empty',
              style: TextStyle(color: color.onSurface.withAlpha(180), fontSize: 18, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text('Start by creating your first note!', style: TextStyle(color: color.outline, fontSize: 14)),
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
              label: Text('#$tag', style: TextStyle(fontSize: 12, color: isSelected ? color.onPrimary : color.primary)),
              backgroundColor: isSelected ? color.primary : color.primaryContainer.withAlpha(100),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              side: BorderSide.none,
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _isSearching = true;
                  _searchController.text = tag;
                  context.read<NoteBloc>().add(SearchNotesEvent(tag));
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchSuggestions(List<NoteEntity> notes, ColorScheme color) {
    final query = _searchController.text.toLowerCase();
    final suggestions = notes.where((n) => n.title.toLowerCase().contains(query) || n.tags.any((t) => t.toLowerCase().contains(query))).take(5).toList();
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: suggestions.map((n) => ListTile(
          leading: const Icon(Icons.history_rounded, size: 18),
          title: Text(n.title.isEmpty ? 'Untitled Note' : n.title, style: const TextStyle(fontSize: 14)),
          onTap: () {
            setState(() {
              _isSearching = false;
              _searchController.clear();
            });
            Navigator.push(context, MaterialPageRoute(builder: (context) => NotePage(note: n)));
          },
        )).toList(),
      ),
    );
  }
}
