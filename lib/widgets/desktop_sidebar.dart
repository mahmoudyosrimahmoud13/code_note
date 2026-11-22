import '../online/chat/chat_store.dart';
import '../online/online_service.dart';
import '../online/shown_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../constants/app_info.dart';
import '../constants/themes.dart';
import '../features/notes/domain/entities/note.dart';
import '../features/notes/domain/entities/note_group.dart';
import '../features/notes/presentation/bloc/note_group_bloc.dart';
import '../features/notes/presentation/bloc/note_group_event.dart';
import '../features/settings/presentation/bloc/settings_bloc.dart';
import '../features/settings/presentation/bloc/settings_state.dart';
import 'brand.dart';
import 'user_avatar.dart';

/// One entry in the sidebar's main navigation.
class SidebarView {
  const SidebarView({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.count,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int count;
}

/// The desktop sidebar: brand, New note, views with counts, folders
/// (click to open, drop a note to move it), tags, and the profile.
class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    super.key,
    required this.views,
    required this.selectedView,
    required this.onSelectView,
    required this.groups,
    required this.notes,
    required this.onOpenGroup,
    required this.onNewGroup,
    required this.tags,
    required this.selectedTag,
    required this.onSelectTag,
    required this.onNewNote,
    required this.onSearch,
    required this.onOpenSettings,
    this.onNewFromTemplate,
    this.onChats,
    this.onAskNotes,
    this.onGist,
    this.onTerminal,
  });

  final List<SidebarView> views;
  final int selectedView;
  final ValueChanged<int> onSelectView;
  final List<NoteGroupEntity> groups;
  final List<NoteEntity> notes;
  final ValueChanged<NoteGroupEntity> onOpenGroup;
  final VoidCallback onNewGroup;
  final List<String> tags;
  final String? selectedTag;
  final ValueChanged<String?> onSelectTag;
  final VoidCallback onNewNote;
  final VoidCallback onSearch;
  final VoidCallback onOpenSettings;
  final VoidCallback? onNewFromTemplate;
  final VoidCallback? onAskNotes;

  /// CodeNote Online: opens the chats.
  final VoidCallback? onChats;
  final VoidCallback? onGist;
  final VoidCallback? onTerminal;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final liveNotes = {
      for (final n in notes)
        if (!n.isTrashed && !n.isArchived) n.id: n,
    };

    return Container(
      width: 264,
      decoration: BoxDecoration(
        color: color.surfaceContainerLow,
        border: Border(right: BorderSide(color: color.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brand
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              children: [
                const BrandMark(size: 30),
                const SizedBox(width: 10),
                Text('codenote',
                    style: monoStyle(context, size: 16, weight: FontWeight.w700)),
                const SizedBox(width: 2),
                const BlinkingCursor(width: 8, height: 15),
              ],
            ),
          ),
          // New note + search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onNewNote,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('New note'),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: 'Search (Ctrl+F)',
                  onPressed: onSearch,
                  icon: const Icon(Icons.search_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                if (onNewFromTemplate != null)
                  Expanded(
                    child: _ToolButton(
                        icon: Icons.dashboard_customize_outlined,
                        label: 'template',
                        onTap: onNewFromTemplate!),
                  ),
                if (onAskNotes != null)
                  Expanded(
                    child: _ToolButton(
                        icon: Icons.auto_awesome_outlined, label: 'ask', onTap: onAskNotes!),
                  ),
                if (onGist != null)
                  Expanded(
                    child: _ToolButton(
                        icon: Icons.download_rounded, label: 'gist', onTap: onGist!),
                  ),
                if (onTerminal != null)
                  Expanded(
                    child: _ToolButton(
                        icon: Icons.terminal_rounded, label: 'shell', onTap: onTerminal!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                if (onChats != null) _ChatsItem(onTap: onChats!),
                for (var i = 0; i < views.length; i++)
                  _SidebarItem(
                    icon: selectedView == i ? views[i].selectedIcon : views[i].icon,
                    label: views[i].label,
                    count: views[i].count,
                    selected: selectedView == i && selectedTag == null,
                    onTap: () {
                      onSelectTag(null);
                      onSelectView(i);
                    },
                  ),
                _SectionTitle(
                  'folders',
                  trailing: IconButton(
                    tooltip: 'New folder',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    onPressed: onNewGroup,
                    icon: Icon(Icons.add_rounded, color: tokens.subtle),
                  ),
                ),
                if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Text('no folders yet',
                        style: monoStyle(context, size: 11, color: tokens.subtle)),
                  ),
                for (final group in groups)
                  _FolderItem(
                    group: group,
                    count: group.noteIds.where(liveNotes.containsKey).length,
                    onTap: () => onOpenGroup(group),
                  ),
                if (tags.isNotEmpty) ...[
                  _SectionTitle('tags · ${tags.length}'),
                  _TagCloud(tags: tags, selected: selectedTag, onSelect: onSelectTag),
                ],
              ],
            ),
          ),
          // Profile + settings
          Divider(height: 1, color: color.outlineVariant),
          BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, state) {
              final s = state is SettingsLoaded ? state.settings : null;
              return ListenableBuilder(
                listenable: OnlineService.instance,
                builder: (context, _) {
              final shown = ShownProfile.of(s);
              return InkWell(
                onTap: onOpenSettings,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    children: [
                      Hero(
                        tag: 'user_profile_photo',
                        child: UserAvatar(
                          imageUrl: shown.imageUrl,
                          seed: shown.seed,
                          radius: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(shown.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge),
                            Text(shown.online && shown.handle.isNotEmpty ? 'v$appVersion · @${shown.handle}' : 'v$appVersion · local-only',
                                style: monoStyle(context,
                                    size: 10, color: tokens.subtle)),
                          ],
                        ),
                      ),
                      Icon(Icons.settings_outlined, size: 20, color: tokens.subtle),
                    ],
                  ),
                ),
              );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 4, 4),
      child: Row(
        children: [
          Text('// $text',
              style: monoStyle(context,
                  size: 11, weight: FontWeight.w700, color: context.tokens.subtle)),
          const Spacer(),
          if (trailing != null) SizedBox(height: 28, child: trailing!),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? color.primary.withAlpha(36) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 20, color: selected ? color.primary : color.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? color.primary : color.onSurface,
                      )),
                ),
                if (count > 0)
                  Text('$count',
                      style: monoStyle(context,
                          size: 11,
                          color: selected ? color.primary : context.tokens.subtle)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A folder in the sidebar. Drop a note on it to move the note in.
class _FolderItem extends StatelessWidget {
  const _FolderItem({required this.group, required this.count, required this.onTap});
  final NoteGroupEntity group;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return DragTarget<NoteEntity>(
      onWillAcceptWithDetails: (d) => !group.noteIds.contains(d.data.id),
      onAcceptWithDetails: (d) {
        context.read<NoteGroupBloc>().add(UpdateGroupEvent(
            group.copyWith(noteIds: [...group.noteIds, d.data.id])));
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Moved to ${group.name}/')));
      },
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Material(
            color: hovering ? color.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(hovering ? Icons.drive_file_move_rounded : Icons.folder_outlined,
                        size: 19, color: color.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('${group.name}/',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: monoStyle(context, size: 13)),
                    ),
                    Text('$count',
                        style: monoStyle(context, size: 11, color: context.tokens.subtle)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}


class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: switch (label) {
        'template' => 'New from template',
        'ask' => 'Ask your notes (AI)',
        'shell' => 'Terminal (sandboxed)',
        'chats' => 'Chats',
        _ => 'Import from GitHub Gist',
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Icon(icon, size: 18, color: tokens.subtle),
              const SizedBox(height: 3),
              Text(label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: monoStyle(context, size: 10, color: tokens.subtle)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chats, at the top of the sidebar, with the unread count.
class _ChatsItem extends StatelessWidget {
  const _ChatsItem({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: ChatStore.instance,
      builder: (context, _) {
        final n = ChatStore.instance.totalUnread;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(
                  children: [
                    Icon(Icons.forum_outlined, size: 20, color: n > 0 ? color.primary : color.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Chats',
                          style: TextStyle(
                            fontWeight: n > 0 ? FontWeight.w700 : FontWeight.w500,
                            color: color.onSurface,
                          )),
                    ),
                    if (n > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: color.primary, borderRadius: BorderRadius.circular(10)),
                        child: Text(n > 99 ? '99+' : '$n',
                            style: monoStyle(context, size: 11, weight: FontWeight.w700, color: color.onPrimary)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tags as small chips. Long lists show the first few and a "more" chip,
/// so the folders above stay in view.
class _TagCloud extends StatefulWidget {
  const _TagCloud({required this.tags, required this.selected, required this.onSelect});
  final List<String> tags;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  State<_TagCloud> createState() => _TagCloudState();
}

class _TagCloudState extends State<_TagCloud> {
  static const _shown = 8;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final tags = widget.tags;
    var visible = _all || tags.length <= _shown + 2 ? tags : tags.take(_shown).toList();
    // Keep the selected tag visible even when the list is folded.
    if (widget.selected != null && !visible.contains(widget.selected)) {
      visible = [...visible, widget.selected!];
    }
    Widget chip(String text, {required bool on, required VoidCallback onTap, bool muted = false}) {
      return Material(
        color: on ? color.primary.withAlpha(46) : color.surfaceContainerHighest.withAlpha(muted ? 0 : 120),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(text,
                style: monoStyle(context,
                    size: 11.5,
                    weight: on ? FontWeight.w700 : FontWeight.w400,
                    color: on ? color.primary : (muted ? tokens.subtle : color.onSurfaceVariant))),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 8, 12),
      child: Wrap(
        spacing: 5,
        runSpacing: 5,
        children: [
          for (final tag in visible)
            chip('#$tag',
                on: widget.selected == tag,
                onTap: () => widget.onSelect(widget.selected == tag ? null : tag)),
          if (tags.length > _shown + 2)
            chip(_all ? 'show less' : '+${tags.length - _shown} more',
                on: false, muted: true, onTap: () => setState(() => _all = !_all)),
        ],
      ),
    );
  }
}
