import 'package:flutter/material.dart';

import '../../constants/themes.dart';
import '../models.dart';
import '../online_service.dart';
import 'common.dart';

/// For admins: numbers, people, sign-up and announcements.
class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin dashboard'),
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(icon: Icon(Icons.insights_rounded), text: 'Overview'),
            Tab(icon: Icon(Icons.people_alt_outlined), text: 'People'),
            Tab(icon: Icon(Icons.tune_rounded), text: 'Sign-up'),
            Tab(icon: Icon(Icons.campaign_outlined), text: 'Announcements'),
          ]),
        ),
        body: const TabBarView(children: [_Overview(), _People(), _SignUp(), _Announcements()]),
      ),
    );
  }
}

class _Overview extends StatefulWidget {
  const _Overview();

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  AdminStats? _stats;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await OnlineService.instance.backend.adminStats();
      if (mounted) setState(() => _stats = s);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    if (s == null) return _error != null ? EmptyState(icon: Icons.error_outline_rounded, title: "Can't load the numbers", body: _error) : const Center(child: CircularProgressIndicator());
    final cards = [
      (Icons.people_alt_rounded, 'People', s['users']),
      (Icons.bolt_rounded, 'Active today', s['active_today']),
      (Icons.wifi_tethering_rounded, 'Online now', s['online']),
      (Icons.forum_rounded, 'Chats', s['chats']),
      (Icons.groups_rounded, 'Groups', s['groups']),
      (Icons.chat_bubble_rounded, 'Messages', s['messages']),
      (Icons.today_rounded, 'Messages today', s['messages_today']),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.extent(
        padding: const EdgeInsets.all(16),
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: [
          for (final (icon, label, value) in cards)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppBrand.radius),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withAlpha(160)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$value', style: monoStyle(context, size: 26, weight: FontWeight.w700)),
                  Text(label, style: TextStyle(color: context.tokens.subtle)),
                ]),
              ]),
            ),
        ],
      ),
    );
  }
}

class _People extends StatefulWidget {
  const _People();

  @override
  State<_People> createState() => _PeopleState();
}

class _PeopleState extends State<_People> {
  final _q = TextEditingController();
  List<Profile>? _people;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await OnlineService.instance.backend.adminUsers(_q.text.trim());
      if (mounted) setState(() => _people = p);
    } catch (e) {
      if (mounted) showSnack(context, e, error: true);
    }
  }

  Future<void> _update(Profile p, {bool? disabled, bool? admin}) async {
    if (disabled == true &&
        !await confirm(context,
            title: 'Turn off ${p.name}\'s account?',
            body: "They're signed out everywhere and can't sign in until you turn it back on.",
            action: 'Turn off')) {
      return;
    }
    if (!mounted) return;
    await attempt(context, () async {
      final updated = await OnlineService.instance.backend.adminUpdateUser(p.id, disabled: disabled, admin: admin);
      setState(() => _people = [for (final x in _people!) x.id == p.id ? updated : x]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = Theme.of(context).colorScheme;
    final me = OnlineService.instance.me?.id;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _q,
          onSubmitted: (_) => _load(),
          decoration: InputDecoration(
            hintText: 'Search by name, username or email',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _load),
          ),
        ),
      ),
      Expanded(
        child: _people == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(children: [
                for (final p in _people!)
                  ListTile(
                    leading: Avatar.profile(p, size: 40),
                    title: Row(children: [
                      Flexible(child: Text(p.name, overflow: TextOverflow.ellipsis)),
                      if (p.isAdmin) ...[const SizedBox(width: 6), Text('admin', style: monoStyle(context, size: 11, color: color.primary))],
                      if (p.isDisabled) ...[const SizedBox(width: 6), Text('turned off', style: monoStyle(context, size: 11, color: color.error))],
                    ]),
                    subtitle: Text('${p.handle} · ${p.email ?? ''}', style: TextStyle(fontSize: 12, color: tokens.subtle)),
                    trailing: p.id == me
                        ? const Text('you')
                        : PopupMenuButton<String>(
                            onSelected: (v) => switch (v) {
                              'admin' => _update(p, admin: !p.isAdmin),
                              _ => _update(p, disabled: !p.isDisabled),
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(value: 'admin', child: Text(p.isAdmin ? 'Remove admin' : 'Make admin')),
                              PopupMenuItem(value: 'disable', child: Text(p.isDisabled ? 'Turn account on' : 'Turn account off')),
                            ],
                          ),
                  ),
              ]),
      ),
    ]);
  }
}

class _SignUp extends StatefulWidget {
  const _SignUp();

  @override
  State<_SignUp> createState() => _SignUpState();
}

class _SignUpState extends State<_SignUp> {
  AppSettingsInfo? _s;
  final _limit = TextEditingController();
  final _message = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _limit.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await OnlineService.instance.backend.adminSettings();
      if (!mounted) return;
      setState(() {
        _s = s;
        _limit.text = '${s.userLimit}';
        _message.text = s.maintenanceMessage;
      });
    } catch (e) {
      if (mounted) showSnack(context, e, error: true);
    }
  }

  Future<void> _save({bool? signup}) async {
    await attempt(context, () async {
      final s = await OnlineService.instance.backend.adminUpdateSettings(
        signupEnabled: signup,
        userLimit: int.tryParse(_limit.text.trim()),
        maintenanceMessage: _message.text.trim(),
      );
      setState(() => _s = s);
    }, done: 'Saved');
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.symmetric(vertical: 12), children: [
      Panel(children: [
        SwitchListTile(
          secondary: const Icon(Icons.how_to_reg_outlined),
          title: const Text('New people can sign up'),
          subtitle: const Text('Turn off to keep this server to the people already on it'),
          value: s.signupEnabled,
          onChanged: (v) => _save(signup: v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: TextField(
            controller: _limit,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Most accounts allowed', prefixIcon: Icon(Icons.people_outline_rounded)),
          ),
        ),
      ]),
      const SectionLabel('message on the sign-in screen'),
      Panel(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _message,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(hintText: 'For example: "Maintenance tonight 22:00 to 23:00". Leave empty for none.'),
          ),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(onPressed: () => _save(), icon: const Icon(Icons.save_outlined), label: const Text('Save')),
      ),
    ]);
  }
}

class _Announcements extends StatefulWidget {
  const _Announcements();

  @override
  State<_Announcements> createState() => _AnnouncementsState();
}

class _AnnouncementsState extends State<_Announcements> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _kind = 'info';
  List<Announcement>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await OnlineService.instance.backend.announcements();
      if (mounted) setState(() => _list = l);
    } catch (_) {
      if (mounted) setState(() => _list = const []);
    }
  }

  Future<void> _post() async {
    if (_title.text.trim().isEmpty) {
      showSnack(context, 'Give it a title.', error: true);
      return;
    }
    final ok = await attempt(context,
        () => OnlineService.instance.backend.announce(title: _title.text.trim(), body: _body.text.trim(), kind: _kind),
        done: 'Sent to everyone');
    if (ok) {
      _title.clear();
      _body.clear();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ListView(padding: const EdgeInsets.symmetric(vertical: 12), children: [
      Panel(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _title, maxLength: 120, decoration: const InputDecoration(labelText: 'Title', counterText: '')),
            const SizedBox(height: 10),
            TextField(controller: _body, maxLines: 4, minLines: 2, decoration: const InputDecoration(labelText: 'Message')),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'info', icon: Icon(Icons.campaign_outlined), label: Text('Info')),
                ButtonSegment(value: 'update', icon: Icon(Icons.rocket_launch_outlined), label: Text('Update')),
                ButtonSegment(value: 'warning', icon: Icon(Icons.warning_amber_rounded), label: Text('Warning')),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _post, icon: const Icon(Icons.send_rounded), label: const Text('Send to everyone')),
          ]),
        ),
      ]),
      const SectionLabel('sent before'),
      if (_list == null) const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
      if (_list != null && _list!.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('Nothing yet', style: TextStyle(color: tokens.subtle))),
      if (_list != null && _list!.isNotEmpty)
        Panel(children: [
          for (final a in _list!)
            SwitchListTile(
              title: Text(a.title),
              subtitle: Text('${a.kind} · ${a.createdAt == null ? '' : chatTime(a.createdAt!)}${a.body.isEmpty ? '' : '\n${a.body}'}'),
              isThreeLine: a.body.isNotEmpty,
              value: a.active,
              onChanged: (v) async {
                final ok = await attempt(context, () => OnlineService.instance.backend.setAnnouncementActive(a.id, v));
                if (ok) _load();
              },
            ),
        ]),
    ]);
  }
}
