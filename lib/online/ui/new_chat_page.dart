import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../constants/themes.dart';
import '../chat/chat_store.dart';
import '../models.dart';
import '../online_service.dart';
import 'common.dart';
import 'profile_page.dart';

/// What a CodeNote QR code holds: codenote-user:<id>
const qrPrefix = 'codenote-user:';

bool get _canScan => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Find someone to chat with, start a group, or use a QR code. Pops with
/// the chat id to open.
class NewChatPage extends StatefulWidget {
  const NewChatPage({super.key});

  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Profile> _results = const [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    final text = v.trim();
    if (text.length < 2) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(text));
  }

  Future<void> _search(String text) async {
    setState(() => _searching = true);
    try {
      final found = await ChatStore.instance.backend.searchUsers(text);
      if (mounted && _q.text.trim() == text) {
        setState(() {
          _results = found;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _start(Profile p) async {
    try {
      final chat = await ChatStore.instance.openDirect(p.id);
      if (mounted) Navigator.pop(context, chat.id);
    } catch (e) {
      if (mounted) showSnack(context, e, error: true);
    }
  }

  Future<void> _scan() async {
    final id = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanQrPage()));
    if (id == null || !mounted) return;
    if (id == OnlineService.instance.me?.id) {
      showSnack(context, "That's your own code.");
      return;
    }
    try {
      final page = await ChatStore.instance.backend.user(id);
      if (mounted) await _start(page.profile);
    } catch (e) {
      if (mounted) showSnack(context, e, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(title: const Text('New chat')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _q,
              autofocus: true,
              onChanged: _changed,
              decoration: InputDecoration(
                hintText: 'Name, @username or email',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
              ),
            ),
          ),
          if (_q.text.trim().length < 2) ...[
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.group_add_rounded)),
              title: const Text('New group'),
              subtitle: const Text('Chat with several people, share notes and code'),
              onTap: () async {
                final id = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const NewGroupPage()));
                if (id != null && context.mounted) Navigator.pop(context, id);
              },
            ),
            if (_canScan)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.qr_code_scanner_rounded)),
                title: const Text('Scan a QR code'),
                subtitle: const Text("Point the camera at someone's CodeNote code"),
                onTap: _scan,
              ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.qr_code_2_rounded)),
              title: const Text('My QR code'),
              subtitle: const Text('Others scan it to start a chat with you'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyQrPage())),
            ),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          if (_q.text.trim().length >= 2 && _results.isEmpty && !_searching && _error == null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Nobody found. Check the spelling, or ask for their @username.',
                  textAlign: TextAlign.center, style: TextStyle(color: tokens.subtle)),
            ),
          for (final p in _results)
            ListTile(
              leading: Avatar.profile(p, size: 42, online: ChatStore.instance.isOnline(p)),
              title: Text(p.name),
              subtitle: Text(p.handle, style: monoStyle(context, size: 12, color: tokens.subtle)),
              trailing: IconButton(
                tooltip: 'Profile',
                icon: const Icon(Icons.person_outline_rounded),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(userId: p.id))),
              ),
              onTap: () => _start(p),
            ),
        ],
      ),
    );
  }
}

/// Pick people (for a new group or to add to one). Pops with their ids.
class PeoplePicker extends StatefulWidget {
  const PeoplePicker({super.key, this.exclude = const {}, this.title = 'Add people', this.action = 'Add'});
  final Set<String> exclude;
  final String title;
  final String action;

  @override
  State<PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<PeoplePicker> {
  final _q = TextEditingController();
  final _picked = <String, Profile>{};
  List<Profile> _results = const [];
  Timer? _debounce;

  /// People I already chat with, for a quick pick.
  List<Profile> get _recent => [
        for (final c in ChatStore.instance.chats)
          if (!c.isGroup && c.otherUser != null && !c.otherUser!.isDeleted && !widget.exclude.contains(c.otherUser!.id)) c.otherUser!
      ];

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    if (v.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await ChatStore.instance.backend.searchUsers(v.trim());
        if (mounted) setState(() => _results = r.where((p) => !widget.exclude.contains(p.id)).toList());
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = _q.text.trim().length >= 2 ? _results : _recent;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, _picked.values.toList()),
            child: Text(_picked.isEmpty ? widget.action : '${widget.action} (${_picked.length})'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        if (_picked.isNotEmpty)
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final p in _picked.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InputChip(
                      avatar: Avatar.profile(p, size: 24),
                      label: Text(p.name.split(' ').first),
                      onDeleted: () => setState(() => _picked.remove(p.id)),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _q,
            onChanged: _changed,
            decoration: const InputDecoration(hintText: 'Search people', prefixIcon: Icon(Icons.search_rounded)),
          ),
        ),
        if (_q.text.trim().length < 2 && list.isNotEmpty) const SectionLabel('people you chat with', padding: EdgeInsets.fromLTRB(20, 4, 20, 4)),
        Expanded(
          child: ListView(children: [
            for (final p in list)
              CheckboxListTile(
                value: _picked.containsKey(p.id),
                onChanged: (v) => setState(() => v == true ? _picked[p.id] = p : _picked.remove(p.id)),
                secondary: Avatar.profile(p, size: 40),
                title: Text(p.name),
                subtitle: Text(p.handle),
              ),
          ]),
        ),
      ]),
    );
  }
}

class NewGroupPage extends StatefulWidget {
  const NewGroupPage({super.key});

  @override
  State<NewGroupPage> createState() => _NewGroupPageState();
}

class _NewGroupPageState extends State<NewGroupPage> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  List<Profile> _members = const [];
  String? _imageUrl;
  bool _adminOnly = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickMembers() async {
    final picked = await Navigator.push<List<Profile>>(
        context, MaterialPageRoute(builder: (_) => PeoplePicker(title: 'Group members', action: 'Done', exclude: {..._members.map((m) => m.id)})));
    if (picked != null) setState(() => _members = [..._members, ...picked]);
  }

  Future<void> _pickImage() async {
    final url = await pickAndUploadPicture(context);
    if (url != null) setState(() => _imageUrl = url);
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'Give the group a name.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final chat = await ChatStore.instance.createGroup(
        name: _name.text.trim(),
        description: _description.text.trim(),
        imageUrl: _imageUrl,
        memberIds: [for (final m in _members) m.id],
        adminOnly: _adminOnly,
      );
      if (mounted) Navigator.pop(context, chat.id);
    } catch (e) {
      if (mounted) showSnack(context, e, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New group')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _create,
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded),
        label: const Text('Create group'),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
        const SizedBox(height: 12),
        Center(
          child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: _pickImage,
            child: Stack(children: [
              Avatar(seed: _name.text, name: _name.text, imageUrl: _imageUrl, size: 96, group: true),
              Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(radius: 16, backgroundColor: color.primary, child: Icon(Icons.photo_camera_rounded, size: 16, color: color.onPrimary)),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: TextField(
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Group name', counterText: ''),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _description,
            maxLines: 3,
            minLines: 1,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Description (optional)', counterText: ''),
          ),
        ),
        SwitchListTile(
          value: _adminOnly,
          onChanged: (v) => setState(() => _adminOnly = v),
          title: const Text('Only admins can send messages'),
          subtitle: const Text('Good for announcements and course groups'),
        ),
        SectionLabel('${_members.length} ${_members.length == 1 ? 'member' : 'members'} plus you',
            trailing: TextButton.icon(onPressed: _pickMembers, icon: const Icon(Icons.person_add_alt_rounded), label: const Text('Add'))),
        for (final m in _members)
          ListTile(
            leading: Avatar.profile(m, size: 38),
            title: Text(m.name),
            subtitle: Text(m.handle),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _members = _members.where((x) => x.id != m.id).toList()),
            ),
          ),
      ]),
    );
  }
}

/// Picks a picture, uploads it, and returns its web address.
Future<String?> pickAndUploadPicture(BuildContext context) async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
  if (picked == null) return null;
  try {
    final bytes = await picked.readAsBytes();
    final png = picked.name.toLowerCase().endsWith('.png');
    return await ChatStore.instance.backend
        .uploadImage(bytes, contentType: png ? 'image/png' : 'image/jpeg', extension: png ? 'png' : 'jpg');
  } catch (e) {
    if (context.mounted) showSnack(context, e, error: true);
    return null;
  }
}

/// My code, for others to scan.
class MyQrPage extends StatelessWidget {
  const MyQrPage({super.key});

  @override
  Widget build(BuildContext context) {
    final me = OnlineService.instance.me;
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    if (me == null) return const Scaffold(body: SizedBox.shrink());
    return Scaffold(
      appBar: AppBar(title: const Text('My QR code')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: color.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppBrand.radius),
              border: Border.all(color: color.outlineVariant.withAlpha(160)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Avatar.profile(me, size: 64),
              const SizedBox(height: 10),
              Text(me.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text(me.handle, style: monoStyle(context, size: 13, color: tokens.subtle)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: QrImageView(
                  data: '$qrPrefix${me.id}',
                  size: 220,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: Color(0xFF1D1F38)),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: Color(0xFF1D1F38)),
                ),
              ),
              const SizedBox(height: 16),
              Text('People scan this in CodeNote to start a chat with you.', textAlign: TextAlign.center, style: TextStyle(color: tokens.subtle)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Scans a CodeNote QR code. Pops with the person's id.
class ScanQrPage extends StatefulWidget {
  const ScanQrPage({super.key});

  @override
  State<ScanQrPage> createState() => _ScanQrPageState();
}

class _ScanQrPageState extends State<ScanQrPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a QR code')),
      body: Stack(children: [
        MobileScanner(
          onDetect: (capture) {
            if (_done) return;
            for (final code in capture.barcodes) {
              final raw = code.rawValue ?? '';
              if (raw.startsWith(qrPrefix)) {
                _done = true;
                Navigator.pop(context, raw.substring(qrPrefix.length));
                return;
              }
            }
          },
        ),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(28),
            ),
          ),
        ),
        const Positioned(
          left: 24,
          right: 24,
          bottom: 40,
          child: Text("Point the camera at someone's CodeNote QR code",
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16, shadows: [Shadow(blurRadius: 8)])),
        ),
      ]),
    );
  }
}
