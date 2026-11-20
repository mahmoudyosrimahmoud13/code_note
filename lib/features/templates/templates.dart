import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../constants/themes.dart';
import '../../helpers/helper_methods.dart';
import '../notes/data/models/note_model.dart';
import '../notes/domain/entities/block.dart';
import '../notes/domain/entities/language.dart';
import '../notes/domain/entities/note.dart';

/// A starting point for a new note.
class NoteTemplate {
  const NoteTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.title,
    required this.tags,
    required this.blocks,
    this.custom = false,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;
  final String title;
  final List<String> tags;
  final List<BlockEntity> blocks;
  final bool custom;

  /// A brand-new note from this template, with fresh ids everywhere.
  NoteEntity newNote() {
    final today = DateTime.now();
    final date =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    String fill(String? s) => (s ?? '').replaceAll('{date}', date);
    return NoteEntity(
      id: uuid.generate(),
      title: fill(title),
      tags: List.of(tags),
      lastModified: today,
      blocks: [
        for (final b in blocks)
          switch (b) {
            CodeBlockEntity c => CodeBlockEntity(id: uuid.generate(), text: fill(c.text), language: c.language, runRole: c.runRole),
            MarkdownBlockEntity m => MarkdownBlockEntity(id: uuid.generate(), text: fill(m.text)),
            ImageBlockEntity i => ImageBlockEntity(id: uuid.generate(), imagePath: i.imagePath ?? ''),
            _ => NoteBlockEntity(id: uuid.generate(), text: fill(b.text)),
          },
      ],
    );
  }
}

class Templates {
  Templates._();

  static final builtIn = <NoteTemplate>[
    NoteTemplate(
      id: 'bug',
      name: 'Bug report',
      description: 'Steps, expected vs actual, logs, and the fix',
      icon: Icons.bug_report_outlined,
      title: 'Bug: ',
      tags: const ['bug'],
      blocks: const [
        MarkdownBlockEntity(id: 'b1', text: '''
### What happened
### Steps to reproduce
1.
2.
### Expected
### Actual'''),
        CodeBlockEntity(id: 'b2', language: Language.bash, text: '# error output or logs'),
        MarkdownBlockEntity(id: 'b3', text: '### Fix\n'),
      ],
    ),
    NoteTemplate(
      id: 'devlog',
      name: 'Daily dev log',
      description: 'What you did, what blocked you, what is next',
      icon: Icons.today_outlined,
      title: 'Dev log {date}',
      tags: const ['devlog'],
      blocks: const [
        MarkdownBlockEntity(id: 'd1', text: '''
### Done today
-
### Blocked by
-
### Tomorrow
- '''),
      ],
    ),
    NoteTemplate(
      id: 'leetcode',
      name: 'Coding problem',
      description: 'LeetCode style: problem, idea, solution, complexity',
      icon: Icons.psychology_outlined,
      title: 'Problem: ',
      tags: const ['leetcode'],
      blocks: const [
        NoteBlockEntity(id: 'l1', text: 'Problem link and short description'),
        MarkdownBlockEntity(id: 'l2', text: '''
### Idea
### Complexity
- Time: O()
- Space: O()'''),
        CodeBlockEntity(id: 'l3', language: Language.python, text: '''
class Solution:
    def solve(self, nums: list[int]) -> int:
        pass'''),
      ],
    ),
    NoteTemplate(
      id: 'meeting',
      name: 'Meeting notes',
      description: 'Who, decisions, action items',
      icon: Icons.groups_outlined,
      title: 'Meeting {date}',
      tags: const ['meeting'],
      blocks: const [
        MarkdownBlockEntity(id: 'm1', text: '''
**People:**

### Notes
-
### Decisions
-
### Action items
- [ ] '''),
      ],
    ),
    NoteTemplate(
      id: 'api',
      name: 'API endpoint',
      description: 'Method, URL, request and response examples',
      icon: Icons.api_outlined,
      title: 'GET /',
      tags: const ['api'],
      blocks: const [
        NoteBlockEntity(id: 'a1', text: 'What this endpoint does and who can call it.'),
        CodeBlockEntity(id: 'a2', language: Language.bash, text: '''
curl -X GET "https://api.example.com/v1/items" \\
  -H "Authorization: Bearer \$TOKEN"'''),
        CodeBlockEntity(id: 'a3', language: Language.json, text: '''
{
  "items": []
}'''),
      ],
    ),
    NoteTemplate(
      id: 'snippet',
      name: 'Snippet with notes',
      description: 'Code plus when to use it and gotchas',
      icon: Icons.code_rounded,
      title: '',
      tags: const ['snippet'],
      blocks: const [
        CodeBlockEntity(id: 's1', language: Language.python, text: ''),
        MarkdownBlockEntity(id: 's2', text: '''
**When to use:**

**Gotchas:**'''),
      ],
    ),
  ];

  // ─── Your own templates ─────────────────────────────────

  static const _boxName = 'appBox';
  static const _key = 'CUSTOM_TEMPLATES';

  static Future<Box> _box() => Hive.isBoxOpen(_boxName)
      ? Future.value(Hive.box(_boxName))
      : Hive.openBox(_boxName);

  static Future<List<NoteTemplate>> custom() async {
    final raw = (await _box()).get(_key);
    if (raw is! String) return const [];
    try {
      return [
        for (final item in json.decode(raw) as List)
          () {
            final note = NoteModel.fromJson(Map<String, dynamic>.from(item as Map));
            return NoteTemplate(
              id: note.id,
              name: note.title.trim().isEmpty ? 'Untitled template' : note.title.trim(),
              description: '${note.blocks.length} blocks',
              icon: Icons.bookmark_outline_rounded,
              title: note.title,
              tags: note.tags,
              blocks: note.blocks,
              custom: true,
            );
          }(),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<List<NoteModel>> _rawCustom() async {
    final raw = (await _box()).get(_key);
    if (raw is! String) return [];
    try {
      return [
        for (final item in json.decode(raw) as List)
          NoteModel.fromJson(Map<String, dynamic>.from(item as Map)),
      ];
    } catch (_) {
      return [];
    }
  }

  /// Saves [note] as a template (a copy; later edits to the note don't change it).
  static Future<void> saveAsTemplate(NoteEntity note) async {
    final list = await _rawCustom();
    final copy = NoteModel.fromEntity(note.copyWith(id: uuid.generate()));
    list.add(copy);
    await (await _box()).put(_key, json.encode([for (final n in list) n.toJson()]));
  }

  static Future<void> delete(String id) async {
    final list = (await _rawCustom())..removeWhere((n) => n.id == id);
    await (await _box()).put(_key, json.encode([for (final n in list) n.toJson()]));
  }
}

/// Lets the person pick a template. Returns a new note, or null.
Future<NoteEntity?> showTemplatePicker(BuildContext context) {
  return showModalBottomSheet<NoteEntity>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _TemplatePicker(),
  );
}

class _TemplatePicker extends StatefulWidget {
  const _TemplatePicker();

  @override
  State<_TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<_TemplatePicker> {
  List<NoteTemplate> _custom = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await Templates.custom();
    if (mounted) setState(() => _custom = c);
  }

  Widget _tile(NoteTemplate t) {
    final color = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.primary.withAlpha(28),
          borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
        ),
        child: Icon(t.icon, color: color.primary, size: 20),
      ),
      title: Text(t.name),
      subtitle: Text(t.description, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: t.custom
          ? IconButton(
              tooltip: 'Delete template',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                await Templates.delete(t.id);
                _load();
              },
            )
          : null,
      onTap: () => Navigator.pop(context, t.newNote()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('New from template', style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final t in Templates.builtIn) _tile(t),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Text('// yours', style: monoStyle(context, size: 11, color: tokens.subtle)),
            ),
            if (_custom.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Text('In any note, open ⋯ > Save as template.',
                    style: TextStyle(color: tokens.subtle)),
              )
            else
              for (final t in _custom) _tile(t),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
