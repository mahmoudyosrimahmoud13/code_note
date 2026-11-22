import 'package:flutter/material.dart';

import '../../constants/themes.dart';
import '../chat/chat_store.dart';
import '../models.dart';
import 'common.dart';
import 'conversation_page.dart';

/// Someone's profile: picture, name, about, groups in common, block.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.userId});
  final String userId;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  UserPage? _page;
  String? _error;

  ChatStore get _store => ChatStore.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _store.backend.user(widget.userId);
      if (mounted) setState(() => _page = p);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _message() async {
    try {
      final chat = await _store.openDirect(widget.userId);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ConversationPage(chatId: chat.id)));
    } catch (e) {
      if (mounted) showSnack(context, e, error: true);
    }
  }

  Future<void> _toggleBlock() async {
    final page = _page!;
    if (!page.blockedByMe &&
        !await confirm(context,
            title: 'Block ${page.profile.name}?',
            body: "They won't be able to message you or find you in search. You can unblock them later.",
            action: 'Block')) {
      return;
    }
    if (!mounted) return;
    final ok = await attempt(context, () async {
      page.blockedByMe ? await _store.backend.unblock(widget.userId) : await _store.backend.block(widget.userId);
    }, done: page.blockedByMe ? 'Unblocked' : 'Blocked');
    if (ok) {
      await _load();
      await _store.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    if (page == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null ? EmptyState(icon: Icons.person_off_outlined, title: "Can't load this profile", body: _error) : const Center(child: CircularProgressIndicator()),
      );
    }
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) => ProfileView(
        profile: page.profile,
        online: _store.isOnline(page.profile),
        lastSeen: _store.lastSeen(page.profile),
        commonGroups: page.commonGroups,
        actions: [
          if (!page.profile.isDeleted && !page.blockedByMe)
            FilledButton.icon(onPressed: _message, icon: const Icon(Icons.chat_bubble_outline_rounded), label: const Text('Message')),
        ],
        footer: [
          if (!page.profile.isDeleted)
            Panel(children: [
              ListTile(
                leading: Icon(page.blockedByMe ? Icons.lock_open_rounded : Icons.block_rounded, color: Theme.of(context).colorScheme.error),
                title: Text(page.blockedByMe ? 'Unblock ${page.profile.name}' : 'Block ${page.profile.name}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: _toggleBlock,
              ),
            ]),
        ],
      ),
    );
  }
}

/// The shared look of a profile (also used for direct chat info).
class ProfileView extends StatelessWidget {
  const ProfileView({
    super.key,
    required this.profile,
    required this.online,
    this.lastSeen,
    this.commonGroups = const [],
    this.actions = const [],
    this.middle = const [],
    this.footer = const [],
    this.heroTag,
  });

  final Profile profile;
  final bool online;
  final DateTime? lastSeen;
  final List<({String id, String name, String? imageUrl})> commonGroups;
  final List<Widget> actions;
  final List<Widget> middle;
  final List<Widget> footer;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final avatar = Avatar.profile(profile, size: 104, online: online);
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Center(child: heroTag == null ? avatar : Hero(tag: heroTag!, child: avatar)),
        const SizedBox(height: 14),
        Text(profile.isDeleted ? 'Deleted account' : profile.name,
            textAlign: TextAlign.center, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        if (profile.username != null)
          Text(profile.handle, textAlign: TextAlign.center, style: monoStyle(context, size: 13, color: tokens.subtle)),
        if (!profile.isDeleted) ...[
          const SizedBox(height: 4),
          Text(lastSeenLabel(online, lastSeen),
              textAlign: TextAlign.center, style: TextStyle(color: online ? tokens.success : tokens.subtle, fontSize: 13)),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 8, children: actions),
        ],
        if (profile.about.isNotEmpty) ...[
          const SectionLabel('about'),
          Panel(children: [Padding(padding: const EdgeInsets.all(16), child: Text(profile.about, style: const TextStyle(height: 1.45)))]),
        ],
        ...middle,
        if (commonGroups.isNotEmpty) ...[
          SectionLabel('${commonGroups.length} ${commonGroups.length == 1 ? 'group' : 'groups'} in common'),
          Panel(children: [
            for (final g in commonGroups)
              ListTile(
                leading: Avatar(seed: g.id, name: g.name, imageUrl: g.imageUrl, size: 38, group: true),
                title: Text(g.name),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationPage(chatId: g.id))),
              ),
          ]),
        ],
        if (footer.isNotEmpty) ...[const SizedBox(height: 20), ...footer],
      ]),
    );
  }
}
