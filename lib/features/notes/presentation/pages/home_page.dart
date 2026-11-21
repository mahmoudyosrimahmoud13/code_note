import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../constants/app_info.dart';
import '../../../../constants/themes.dart';
import '../../../../core/services/log_service.dart';
import '../../../../core/services/log_viewer_page.dart';
import '../../../../core/services/sharing_service.dart';
import '../../../../core/util/platform_helper.dart';
import 'package:file_selector/file_selector.dart';
import '../../../workspace/workspace_actions.dart';
import '../../../../core/services/open_files_service.dart';
import '../../../../core/services/update_dialog.dart';
import '../../../../core/services/update_service.dart';
import '../../../../injection_container.dart' as di;
import '../../../backup/backup_service.dart';
import '../../../reminders/reminder_service.dart';
import '../../../templates/templates.dart';
import '../../../ai/ask_notes_page.dart';
import '../../../gist/gist_page.dart';
import '../../../backup/codenote_files.dart';
import '../../../runner/run_manager.dart';
import '../../../runner/runtimes_page.dart';
import '../../../runner/sandbox.dart';
import '../../../runner/terminal_page.dart';
import '../../domain/repositories/note_repository.dart';
import 'package:intl/intl.dart';
import '../../../../helpers/helper_methods.dart';
import '../../../../widgets/brand.dart';
import '../../../../widgets/command_palette.dart';
import '../../../../widgets/desktop_sidebar.dart';
import '../../../ai/ai_settings_page.dart';
import '../../../backup/backup_page.dart';
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
    // Desktop: .codenote files opened from the file manager.
    OpenFilesService.instance.start((path) {
      if (mounted) SharingService().openFile(context, path);
    });
    LogService().log('HomePage: ready (local-only).');
    _startReminders();
    // Daily backup to the chosen folder (Windows, Linux), if turned on.
    di.sl<BackupService>().runDailyBackupIfDue();
    // Look for a newer version a few seconds after start (once a day).
    Future.delayed(const Duration(seconds: 3), () async {
      final update = await UpdateService.instance.checkInBackground();
      if (update != null && mounted) showUpdateDialog(context, update);
    });
  }

  Timer? _reminderTimer;

  /// Phones and Mac: re-schedule system notifications.
  /// Windows and Linux: check every 30 seconds and show a pop-up.
  Future<void> _startReminders() async {
    final notes = (await di.sl<NoteRepository>().getNotes()).getOrElse(() => const []);
    if (ReminderService.systemNotifications) {
      ReminderService.instance.syncAll(notes);
      return;
    }
    _reminderTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final state = context.read<NoteBloc>().state;
      if (state is! NoteLoaded || !mounted) return;
      final due = await ReminderService.instance.dueReminders(state.notes);
      for (final note in due) {
        if (!mounted) return;
        await _showReminderPopup(note);
      }
    });
  }

  Future<void> _showReminderPopup(NoteEntity note) {
    final r = note.reminder!;
    return showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(Icons.alarm_rounded, color: c.tokens.pin, size: 32),
        title: Text(note.title.trim().isEmpty ? 'Reminder' : note.title.trim()),
        content: Text(r.message.trim().isEmpty
            ? DateFormat.MMMEd().add_jm().format(r.dateTime)
            : r.message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Dismiss')),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              _openPage(NotePage(note: note));
            },
            child: const Text('Open note'),
          ),
        ],
      ),
    );
  }

  /// Picks a Jupyter notebook and opens it as a note.
  Future<void> _openNotebook() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Jupyter notebook',
        extensions: ['ipynb'],
        mimeTypes: ['application/x-ipynb+json', 'application/json', 'application/octet-stream'],
        uniformTypeIdentifiers: ['public.json', 'public.data'],
      ),
    ]);
    if (file == null || !mounted) return;
    SharingService().openFile(context, file.path);
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    _searchController.dispose();
    SharingService().dispose();
    OpenFilesService.instance.stop();
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

  Future<void> _addFromTemplate() async {
    final note = await showTemplatePicker(context);
    if (note == null || !mounted) return;
    final withTag = _tag == null || note.tags.contains(_tag)
        ? note
        : note.copyWith(tags: [...note.tags, _tag!]);
    _openPage(NotePage(note: withTag));
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
    // Layout follows the window width, not the platform:
    //   wide (>= 1000): full sidebar   medium: slim rail   narrow: phone layout
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1000;
    final medium = width >= 720 && !wide;
    final narrow = !wide && !medium;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _addNote,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _addNote,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _openPalette,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _openPalette,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_isSearching) setState(_closeSearch);
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
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
                  final notes = noteState.notes;
                  final groups = groupState.groups;
                  return Row(
                    children: [
                      if (wide) _buildSidebar(notes, groups),
                      if (medium) _buildRail(),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          // Keep lines readable on very wide screens.
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1400),
                            child: _buildContent(notes, groups, wide: wide),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          bottomNavigationBar: narrow
              ? NavBar(
                  selectedIndex: _view.index,
                  onIndexChanged: (i) => _select(HomeView.values[i]),
                  addNote: _addNote,
                )
              : null,
          floatingActionButton: medium
              ? FloatingActionButton.extended(
                  onPressed: _addNote,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New note'),
                  tooltip: 'New note (Ctrl+N)',
                )
              : null,
        ),
      ),
    );
  }

  void _openSearch() => setState(() => _isSearching = true);

  void _openPage(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  /// Ctrl+K: every action, note and folder in one searchable list.
  void _openPalette() {
    final noteState = context.read<NoteBloc>().state;
    final groupState = context.read<NoteGroupBloc>().state;
    final notes = noteState is NoteLoaded
        ? (noteState.notes.where((n) => !n.isTrashed).toList()
          ..sort((a, b) => b.lastModified.compareTo(a.lastModified)))
        : <NoteEntity>[];
    final groups = groupState is NoteGroupLoaded ? groupState.groups : <NoteGroupEntity>[];
    final settingsBloc = context.read<SettingsBloc>();

    showCommandPalette(context, [
      PaletteItem(label: 'New note', icon: Icons.add_rounded, hint: 'Ctrl+N', run: _addNote, keywords: 'create write'),
      PaletteItem(label: 'New from template', icon: Icons.dashboard_customize_outlined, run: _addFromTemplate, keywords: 'template bug devlog leetcode meeting api snippet'),
      PaletteItem(label: 'Ask your notes', icon: Icons.forum_outlined, run: () => _openPage(const AskNotesPage()), keywords: 'ai question chat search'),
      PaletteItem(label: 'Import from GitHub Gist', icon: Icons.download_rounded, run: () => _openPage(const GistPage()), keywords: 'gist github import export'),
      if (Sandbox.supported) ...[
        PaletteItem(label: 'Terminal', icon: Icons.terminal_rounded, run: () => _openPage(const TerminalPage()), keywords: 'shell bash console command line'),
        PaletteItem(label: 'Runtimes and sandbox', icon: Icons.tune_rounded, run: () => _openPage(const RuntimesPage()), keywords: 'python pip packages bash install update sandbox'),
        if (RunManager.instance.running.isNotEmpty)
          PaletteItem(label: 'Stop all running code (${RunManager.instance.running.length})', icon: Icons.stop_circle_outlined, run: RunManager.instance.stopAll, keywords: 'kill server'),
      ],
      PaletteItem(label: 'Open a .codenote file', icon: Icons.file_open_outlined, run: () => CodenoteFiles.pickAndImport(context), keywords: 'import share file note folder'),
      PaletteItem(label: PlatformHelper.isDesktopOrWeb ? 'Open a folder as a workspace' : 'Open files as a workspace', icon: Icons.folder_open_rounded, run: () => WorkspaceActions.openWorkspace(context), keywords: 'ide directory project files data science'),
      PaletteItem(label: 'Open a data file (CSV, Excel, JSON)', icon: Icons.table_chart_rounded, run: () => WorkspaceActions.openDataFile(context), keywords: 'csv excel xlsx json parquet table data viewer pandas'),
      PaletteItem(label: 'Open a Jupyter notebook (.ipynb)', icon: Icons.menu_book_outlined, run: _openNotebook, keywords: 'jupyter ipynb import notebook colab kaggle'),
      PaletteItem(label: 'New folder', icon: Icons.create_new_folder_outlined, run: _createGroup, keywords: 'group create'),
      PaletteItem(label: 'Search notes', icon: Icons.search_rounded, hint: 'Ctrl+F', run: _openSearch, keywords: 'find grep'),
      for (final view in HomeView.values)
        PaletteItem(
          label: 'Go to ${view.path}',
          icon: Icons.arrow_forward_rounded,
          run: () => _select(view),
          keywords: view.name,
        ),
      PaletteItem(label: 'Backup and restore', icon: Icons.cloud_upload_outlined, run: () => _openPage(const BackupPage()), keywords: 'export import save sync'),
      PaletteItem(label: 'AI assistant settings', icon: Icons.auto_awesome_outlined, run: () => _openPage(const AiSettingsPage()), keywords: 'claude ollama openai model key'),
      PaletteItem(
        label: 'Switch light / dark theme',
        icon: Icons.contrast_rounded,
        keywords: 'mode appearance',
        run: () {
          final st = settingsBloc.state;
          if (st is! SettingsLoaded) return;
          final dark = st.settings.themeMode == 'dark' ||
              (st.settings.themeMode == 'system' &&
                  MediaQuery.platformBrightnessOf(context) == Brightness.dark);
          settingsBloc.add(UpdateSettingsEvent(
              st.settings.copyWith(themeMode: dark ? 'light' : 'dark')));
        },
      ),
      PaletteItem(label: 'Check for updates', icon: Icons.system_update_alt_rounded, run: () async {
        try {
          final update = await UpdateService.instance.check();
          if (!mounted) return;
          if (update == null) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("You're on the newest version.")));
          } else {
            showUpdateDialog(context, update);
          }
        } catch (_) {}
      }),
      PaletteItem(label: 'Settings', icon: Icons.settings_outlined, run: () => _openPage(const SettingsPage()), keywords: 'preferences profile'),
      for (final g in groups)
        PaletteItem(
          label: '${g.name}/',
          icon: Icons.folder_outlined,
          group: 'Folders',
          hint: '${g.noteIds.length}',
          run: () => _openGroup(g),
        ),
      for (final n in notes)
        PaletteItem(
          label: n.title.trim().isEmpty ? 'Untitled' : n.title.trim(),
          icon: n.isPinned ? Icons.push_pin_outlined : Icons.description_outlined,
          group: 'Notes',
          hint: n.tags.isEmpty ? null : '#${n.tags.first}',
          keywords: [
            ...n.tags,
            for (final b in n.blocks.take(3)) (b.text ?? '').split('\n').first,
          ].join(' '),
          run: () => _openPage(NotePage(note: n)),
        ),
    ]);
  }

  void _openGroup(NoteGroupEntity group) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GroupDetailsPage(group: group)),
      );

  Widget _buildSidebar(List<NoteEntity> all, List<NoteGroupEntity> groups) {
    int count(bool Function(NoteEntity) test) => all.where(test).length;
    final tags = all.where((n) => !n.isTrashed).expand((n) => n.tags).toSet().toList()
      ..sort();
    return DesktopSidebar(
      views: [
        SidebarView(
          label: 'Notes',
          icon: Icons.description_outlined,
          selectedIcon: Icons.description_rounded,
          count: count((n) => !n.isArchived && !n.isTrashed),
        ),
        SidebarView(
          label: 'Reminders',
          icon: Icons.alarm_outlined,
          selectedIcon: Icons.alarm_rounded,
          count: count((n) => n.reminder != null && !n.isTrashed),
        ),
        SidebarView(
          label: 'Archive',
          icon: Icons.archive_outlined,
          selectedIcon: Icons.archive_rounded,
          count: count((n) => n.isArchived && !n.isTrashed),
        ),
        SidebarView(
          label: 'Trash',
          icon: Icons.delete_outline_rounded,
          selectedIcon: Icons.delete_rounded,
          count: count((n) => n.isTrashed),
        ),
      ],
      selectedView: _view.index,
      onSelectView: (i) => _select(HomeView.values[i]),
      groups: groups,
      notes: all,
      onOpenGroup: _openGroup,
      onNewGroup: _createGroup,
      tags: tags,
      selectedTag: _tag,
      onSelectTag: (tag) => setState(() {
        _tag = tag;
        if (tag != null && _view != HomeView.notes) _view = HomeView.notes;
      }),
      onNewNote: _addNote,
      onNewFromTemplate: _addFromTemplate,
      onAskNotes: () => _openPage(const AskNotesPage()),
      onGist: () => _openPage(const GistPage()),
      onTerminal: Sandbox.supported ? () => _openPage(const TerminalPage()) : null,
      onSearch: _openSearch,
      onOpenSettings: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const SettingsPage())),
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

  Widget _buildContent(List<NoteEntity> all, List<NoteGroupEntity> allGroups,
      {bool wide = false}) {
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

    final phone = MediaQuery.sizeOf(context).width < 720;
    return CustomScrollView(
      // Always scrollable, so a short list still pulls and settles normally.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // Phones: the header is a real app bar that stays at the top while
        // the notes scroll under it, like other Android apps.
        if (phone)
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            titleSpacing: 0,
            toolbarHeight: 68,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Theme.of(context).colorScheme.primary,
            scrolledUnderElevation: 3,
            shadowColor: Colors.black26,
            title: _buildHeader(visibleCount, allGroups.length, wide: wide),
          )
        else
          SliverToBoxAdapter(
              child: _buildHeader(visibleCount, allGroups.length, wide: wide)),
        if (tags.isNotEmpty && _view != HomeView.trash && !wide)
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
                    onTap: () => _openGroup(groups[i]),
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

  Widget _buildHeader(int noteCount, int groupCount, {bool wide = false}) {
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
            tooltip: 'Search (Ctrl+F)',
            icon: const Icon(Icons.search_rounded),
            onPressed: _openSearch,
          ),
          IconButton(
            tooltip: 'Commands (Ctrl+K)',
            icon: const Icon(Icons.keyboard_command_key_rounded),
            onPressed: _openPalette,
          ),
          // Data science: open a folder, a data file or a notebook.
          PopupMenuButton<String>(
            tooltip: 'Open files, data or a notebook',
            icon: const Icon(Icons.folder_open_rounded),
            onSelected: (v) => switch (v) {
              'workspace' => WorkspaceActions.openWorkspace(context),
              'data' => WorkspaceActions.openDataFile(context),
              _ => _openNotebook(),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'workspace',
                child: ListTile(
                  leading: const Icon(Icons.folder_open_rounded),
                  title: Text(PlatformHelper.isDesktopOrWeb ? 'Open a folder' : 'Open files'),
                  subtitle: const Text('Like an IDE: files, notebooks, run'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'data',
                child: ListTile(
                  leading: Icon(Icons.table_chart_rounded),
                  title: Text('Open a data file'),
                  subtitle: Text('CSV, Excel, JSON: table, stats, charts'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'notebook',
                child: ListTile(
                  leading: Icon(Icons.menu_book_outlined),
                  title: Text('Open a Jupyter notebook'),
                  subtitle: Text('.ipynb from Jupyter, Colab or Kaggle'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          if (_view == HomeView.notes && !wide)
            IconButton(
              tooltip: 'New group',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: _createGroup,
            ),
          if (!wide) BlocBuilder<SettingsBloc, SettingsState>(
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
