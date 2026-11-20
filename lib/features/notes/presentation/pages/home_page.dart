import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../constants/app_info.dart';
import '../../../../constants/themes.dart';
import '../../../../core/services/log_service.dart';
import '../../../../core/services/log_viewer_page.dart';
import '../../../../core/services/sharing_service.dart';
import '../../../../core/util/platform_helper.dart';
import '../../../../helpers/helper_methods.dart';
import '../../../../widgets/brand.dart';
import '../../../../widgets/group_card.dart';
import '../../../../widgets/home_grid_view.dart';
import '../../../../widgets/home_navigation_bar.dart';
import '../../../../widgets/user_avatar.dart';
import '../../../settings/presentation/bloc/settings_bloc.dart';
import '../../../settings/presentation/bloc/settings_event.dart';
import '../../../settings/presentation/bloc/settings_state.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/note_group.dart';
import '../../domain/logic/note_search.dart';
import '../bloc/note_bloc.dart';
import '../bloc/note_event.dart';
import '../bloc/note_group_bloc.dart';
import '../bloc/note_group_event.dart';
import '../bloc/note_group_state.dart';
import '../bloc/note_state.dart';
import 'group_details_page.dart';
import 'note_page.dart';

/// The four views of the home screen, in navigation order.
enum HomeView { notes, reminders, archive, trash }

extension on HomeView {
  String get path => const ['~/notes', '~/reminders', '~/archive', '~/trash'][index];
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  HomeView _view = HomeView.notes;
  bool _isSearching = false;
  String _query = '';
  String? _tag;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _dismissedNoteIds = {};

  int _versionTaps = 0;
  DateTime? _lastVersionTap;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsBloc>().state;
    if (settings is SettingsLoaded) {
      final index = settings.settings.lastSelectedIndex;
      if (index >= 0 && index < HomeView.values.length) {
        _view = HomeView.values[index];
      }
    }
    // Clear out notes that sat in the trash for more than 30 days.
    context.read<NoteBloc>().add(PurgeOldTrashEvent());
    SharingService().init(context);
    LogService().log('HomePage: ready (local-only).');
  }

  @override
  void dispose() {
    _searchController.dispose();
    SharingService().dispose();
    super.dispose();
  }

  void _select(HomeView view) {
    setState(() {
      _view = view;
      _closeSearch();
      _tag = null;
      _dismissedNoteIds.clear();
    });
    final bloc = context.read<SettingsBloc>();
    final state = bloc.state;
    if (state is SettingsLoaded) {
      bloc.add(UpdateSettingsEvent(
          state.settings.copyWith(lastSelectedIndex: view.index)));
    }
  }

  void _closeSearch() {
    _isSearching = false;
    _query = '';
    _searchController.clear();
  }

  void _addNote() {
    final note = NoteEntity(
      id: uuid.generate(),
      title: '',
      tags: _tag == null ? const [] : [_tag!],
      lastModified: DateTime.now(),
      blocks: const [],
    );
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotePage(note: note)));
  }

  void _createGroup() {
    final controller = TextEditingController();
    void create(BuildContext dialogContext) {
      final name = controller.text.trim();
      if (name.isEmpty) return;
      context.read<NoteGroupBloc>().add(AddGroupEvent(NoteGroupEntity(
            id: uuid.generate(),
            name: name,
            noteIds: const [],
            lastModified: DateTime.now(),
          )));
      Navigator.pop(dialogContext);
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: monoStyle(dialogContext, size: 14),
          decoration: const InputDecoration(hintText: 'snippets', prefixText: '~/'),
          onSubmitted: (_) => create(dialogContext),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => create(dialogContext), child: const Text('Create')),
        ],
      ),
    );
  }

  void _emptyTrash(List<NoteEntity> trashed) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Empty the trash?'),
        content: Text(
            '${trashed.length} ${trashed.length == 1 ? 'note' : 'notes'} and their images will be deleted from this device for good.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error,
              foregroundColor: Theme.of(c).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Empty trash'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final bloc = context.read<NoteBloc>();
    for (final note in trashed) {
      bloc.add(DeleteNoteEvent(note.id));
    }
  }

  void _onVersionTap() {
    final now = DateTime.now();
    if (_lastVersionTap == null ||
        now.difference(_lastVersionTap!) > const Duration(seconds: 2)) {
      _versionTaps = 1;
    } else {
      _versionTaps++;
    }
    _lastVersionTap = now;
    if (_versionTaps >= 3) {
      _versionTaps = 0;
      HapticFeedback.heavyImpact();
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const LogViewerPage()));
    }
  }

  // ─── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformHelper.isDesktopOrWeb;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (isDesktop) _buildRail(),
            Expanded(
              // Swiped cards are hidden right away (Dismissible needs that).
              // Once storage reports the change, show the real list again,
              // so an Undo brings the note straight back.
              child: BlocConsumer<NoteBloc, NoteState>(
                listener: (context, state) => _dismissedNoteIds.clear(),
                builder: (context, noteState) =>
                    BlocBuilder<NoteGroupBloc, NoteGroupState>(
                  builder: (context, groupState) {
                    if (noteState is! NoteLoaded || groupState is! NoteGroupLoaded) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return _buildContent(noteState.notes, groupState.groups);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: isDesktop
          ? null
          : NavBar(
              selectedIndex: _view.index,
              onIndexChanged: (i) => _select(HomeView.values[i]),
              addNote: _addNote,
            ),
      floatingActionButton: isDesktop
          ? FloatingActionButton.extended(
              onPressed: _addNote,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New note'),
              tooltip: 'New note',
            )
          : null,
    );
  }

  Widget _buildRail() {
    return NavigationRail(
      selectedIndex: _view.index,
      onDestinationSelected: (i) => _select(HomeView.values[i]),
      labelType: NavigationRailLabelType.all,
      leading: const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: BrandMark(size: 36),
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.description_outlined),
          selectedIcon: Icon(Icons.description_rounded),
          label: Text('Notes'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.alarm_outlined),
          selectedIcon: Icon(Icons.alarm_rounded),
          label: Text('Reminders'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.archive_outlined),
          selectedIcon: Icon(Icons.archive_rounded),
          label: Text('Archive'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.delete_outline_rounded),
          selectedIcon: Icon(Icons.delete_rounded),
          label: Text('Trash'),
        ),
      ],
    );
  }

  Widget _buildContent(List<NoteEntity> all, List<NoteGroupEntity> allGroups) {
    final searching = _isSearching && _query.trim().isNotEmpty;

    // Pick the notes for this view.
    var notes = all.where((n) => !_dismissedNoteIds.contains(n.id));
    switch (_view) {
      case HomeView.notes:
        notes = notes.where((n) => !n.isArchived && !n.isTrashed);
      case HomeView.reminders:
        notes = notes.where((n) => n.reminder != null && !n.isTrashed);
      case HomeView.archive:
        notes = notes.where((n) => n.isArchived && !n.isTrashed);
      case HomeView.trash:
        notes = notes.where((n) => n.isTrashed);
    }
    if (_tag != null) notes = notes.where((n) => n.tags.contains(_tag));
    if (searching) notes = notes.where((n) => noteMatches(n, _query));

    final list = notes.toList();
    if (_view == HomeView.reminders) {
      list.sort((a, b) => a.reminder!.dateTime.compareTo(b.reminder!.dateTime));
    } else {
      list.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    }

    // On the main view, notes that live in a group show inside the group.
    final showGroups = _view == HomeView.notes && !searching && _tag == null;
    final groups = showGroups ? allGroups : const <NoteGroupEntity>[];
    final inGroups = groups.expand((g) => g.noteIds).toSet();
    final loose = showGroups ? list.where((n) => !inGroups.contains(n.id)).toList() : list;
    final pinned = _view == HomeView.notes && !searching
        ? loose.where((n) => n.isPinned).toList()
        : <NoteEntity>[];
    final rest = loose.where((n) => !pinned.contains(n)).toList();

    final tags = all
        .where((n) => !n.isTrashed)
        .expand((n) => n.tags)
        .toSet()
        .toList()
      ..sort();

    final visibleCount = all.where((n) => !n.isTrashed && !n.isArchived).length;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(visibleCount, allGroups.length)),
        if (tags.isNotEmpty && _view != HomeView.trash)
          SliverToBoxAdapter(child: _buildTagBar(tags)),
        if (_view == HomeView.trash && list.isNotEmpty)
          SliverToBoxAdapter(child: _buildTrashBanner(list)),
        if (list.isEmpty && groups.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState())
        else ...[
          if (groups.isNotEmpty) ...[
            SliverToBoxAdapter(child: CommentLabel('groups', count: groups.length)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 300,
                  mainAxisExtent: 210,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => GroupCard(
                    group: groups[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => GroupDetailsPage(group: groups[i])),
                    ),
                  ),
                  childCount: groups.length,
                ),
              ),
            ),
          ],
          if (pinned.isNotEmpty) ...[
            SliverToBoxAdapter(child: CommentLabel('pinned', count: pinned.length)),
            NotesSliverGrid(notes: pinned, onNoteDismissed: _dismissed),
          ],
          if (rest.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: CommentLabel(
                searching
                    ? 'results for "${_query.trim()}"'
                    : (_tag != null ? '#$_tag' : _sectionName()),
                count: rest.length,
              ),
            ),
            NotesSliverGrid(
              notes: rest,
              isTrashView: _view == HomeView.trash,
              onNoteDismissed: _dismissed,
            ),
          ],
        ],
        SliverToBoxAdapter(child: _buildFooter()),
      ],
    );
  }

  void _dismissed(NoteEntity note) => setState(() => _dismissedNoteIds.add(note.id));

  String _sectionName() => switch (_view) {
        HomeView.notes => 'notes',
        HomeView.reminders => 'coming up',
        HomeView.archive => 'archived',
        HomeView.trash => 'trash',
      };

  Widget _buildHeader(int noteCount, int groupCount) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;

    if (_isSearching) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          controller: _searchController,
          autofocus: true,
          style: monoStyle(context, size: 14),
          decoration: InputDecoration(
            hintText: 'grep your notes…',
            hintStyle: monoStyle(context, size: 14, color: tokens.subtle),
            prefixIcon: Icon(Icons.search_rounded, color: color.primary),
            suffixIcon: IconButton(
              tooltip: 'Close search',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(_closeSearch),
            ),
          ),
          onChanged: (q) => setState(() => _query = q),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PromptLine(path: _view.path, size: 18),
                const SizedBox(height: 2),
                Text(
                  '$noteCount ${noteCount == 1 ? 'note' : 'notes'} · $groupCount ${groupCount == 1 ? 'group' : 'groups'} · stored on this device',
                  style: monoStyle(context, size: 11, color: tokens.subtle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => setState(() => _isSearching = true),
          ),
          if (_view == HomeView.notes)
            IconButton(
              tooltip: 'New group',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: _createGroup,
            ),
          BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, state) {
              final settings = state is SettingsLoaded ? state.settings : null;
              return IconButton(
                tooltip: 'Settings',
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsPage())),
                icon: Hero(
                  tag: 'user_profile_photo',
                  child: UserAvatar(
                    imageUrl: settings?.profileImagePath,
                    seed: settings?.userHandle ?? 'codenote',
                    radius: 15,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTagBar(List<String> tags) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        itemCount: tags.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final tag = tags[i];
          final selected = _tag == tag;
          return FilterChip(
            label: Text('#$tag'),
            selected: selected,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (on) {
              HapticFeedback.selectionClick();
              setState(() => _tag = on ? tag : null);
            },
          );
        },
      ),
    );
  }

  Widget _buildTrashBanner(List<NoteEntity> trashed) {
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: color.surfaceContainer,
          borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule_rounded, size: 18, color: context.tokens.subtle),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Notes here are deleted for good after 30 days.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: () => _emptyTrash(trashed),
              style: TextButton.styleFrom(foregroundColor: color.error),
              child: const Text('Empty trash'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    if (_isSearching && _query.trim().isNotEmpty) {
      return TerminalEmptyState(
        command: 'grep -r "${_query.trim()}" ~/notes',
        output: '0 matches',
        hint: 'Try a shorter word, or search by #tag.',
      );
    }
    if (_tag != null) {
      return TerminalEmptyState(
        command: 'ls ${_view.path} | grep #$_tag',
        output: 'nothing tagged #$_tag here',
      );
    }
    return switch (_view) {
      HomeView.notes => TerminalEmptyState(
          command: 'ls ~/notes',
          output: 'total 0',
          hint: 'Your snippets, ideas and docs live here, only on this device.',
          action: FilledButton.icon(
            onPressed: _addNote,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Write your first note'),
          ),
        ),
      HomeView.reminders => const TerminalEmptyState(
          command: 'crontab -l',
          output: 'no reminders scheduled',
          hint: 'Open a note and tap the bell to set one.',
        ),
      HomeView.archive => const TerminalEmptyState(
          command: 'ls ~/archive',
          output: 'total 0',
          hint: 'Swipe a note right to archive it. It stays out of the way, not gone.',
        ),
      HomeView.trash => const TerminalEmptyState(
          command: 'ls ~/trash',
          output: 'clean. nothing to delete.',
          hint: 'Swiped-away notes wait here for 30 days.',
        ),
    };
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 120),
      child: Center(
        child: Semantics(
          excludeSemantics: true,
          child: GestureDetector(
            onTap: _onVersionTap,
            child: Text(
              'codenote v$appVersion · community edition',
              style: monoStyle(context, size: 10, color: context.tokens.subtle.withAlpha(140)),
            ),
          ),
        ),
      ),
    );
  }
}
