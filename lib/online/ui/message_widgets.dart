import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/v4.dart';

import '../../constants/themes.dart';
import '../../core/util/code_languages.dart';
import '../../features/links/link_widgets.dart';
import '../../features/notes/data/models/block_model.dart';
import '../../features/notes/data/models/note_model.dart';
import '../../features/notes/domain/entities/block.dart';
import '../../features/notes/domain/entities/language.dart';
import '../../features/notes/domain/entities/note.dart';
import '../../features/notes/presentation/bloc/note_bloc.dart';
import '../../features/notes/presentation/bloc/note_event.dart';
import '../../features/notes/presentation/pages/image_preview_page.dart';
import '../../features/notes/presentation/pages/note_page.dart';
import '../models.dart';
import 'common.dart';

/// Reads a block that came in a message.
BlockEntity? blockFromPayload(Map<String, dynamic>? payload) {
  if (payload == null) return null;
  try {
    return BlockModel.fromJson(payload).toEntity();
  } catch (_) {
    return null;
  }
}

/// Reads a note that came in a message.
NoteEntity? noteFromPayload(Map<String, dynamic>? payload) {
  if (payload == null) return null;
  try {
    return NoteModel.fromJson({
      'id': 'shared',
      'title': '',
      'lastModified': DateTime.now().toIso8601String(),
      'tags': const <String>[],
      'blocks': const [],
      ...payload,
    });
  } catch (_) {
    return null;
  }
}

/// What goes in a message for a whole note (pictures must already be web
/// addresses; see [prepareNoteForSending]).
Map<String, dynamic> notePayload(NoteEntity note) {
  final json = NoteModel.fromEntity(note).toJson()
    ..remove('isDirty')
    ..remove('lastSyncedAt')
    ..remove('reminder')
    ..remove('groupId')
    ..remove('isPinned')
    ..remove('isArchived')
    ..remove('isTrashed')
    ..remove('trashTimestamp');
  return json;
}

Map<String, dynamic> blockPayload(BlockEntity block) => BlockModel.fromEntity(block).toJson();

/// Saves a received note or block as a new note of mine. Returns it.
NoteEntity saveToMyNotes(BuildContext context, ChatMessage m) {
  const ids = UuidV4();
  NoteEntity note;
  if (m.kind == MessageKind.note) {
    final n = noteFromPayload(m.payload)!;
    note = NoteEntity(
      id: ids.generate(),
      title: n.title,
      tags: n.tags,
      lastModified: DateTime.now(),
      blocks: [for (final b in n.blocks) b.copyWith(id: ids.generate())],
    );
  } else {
    final b = blockFromPayload(m.payload)!;
    final lang = b is CodeBlockEntity ? languageInfo(b.language).label : 'Text';
    note = NoteEntity(
      id: ids.generate(),
      title: '$lang from chat',
      tags: const ['from-chat'],
      lastModified: DateTime.now(),
      blocks: [b.copyWith(id: ids.generate())],
    );
  }
  context.read<NoteBloc>().add(AddNoteEvent(note));
  return note;
}

/// Opens a received note or block: saved as your own note, then shown.
void openAsMyNote(BuildContext context, ChatMessage m) {
  final note = saveToMyNotes(context, m);
  Navigator.push(context, MaterialPageRoute(builder: (_) => NotePage(note: note)));
}

/// A centered line for group updates and days.
class CenterChip extends StatelessWidget {
  const CenterChip(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: color.surfaceContainerHigh.withAlpha(220),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color.onSurfaceVariant), const SizedBox(width: 6)],
          Flexible(
            child: Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: color.onSurfaceVariant, fontWeight: FontWeight.w500)),
          ),
        ]),
      ),
    );
  }
}

/// One message bubble.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.delivery,
    required this.myId,
    this.senderName,
    this.senderSeed,
    this.showTail = true,
    this.replyName,
    this.onTapReply,
    this.onLongPress,
    this.onReact,
    this.onTapFailed,
    this.highlight = false,
  });

  final ChatMessage message;
  final bool mine;
  final Delivery delivery;
  final String? myId;

  /// Group chats: the sender's name over the first bubble of a run.
  final String? senderName;
  final String? senderSeed;
  final bool showTail;
  final String? replyName;
  final VoidCallback? onTapReply;
  final VoidCallback? onLongPress;
  final void Function(String emoji)? onReact;
  final VoidCallback? onTapFailed;
  final bool highlight;

  static const _names = [
    Color(0xFF7B5CFF), Color(0xFF3D7BFF), Color(0xFFD45CF0), Color(0xFF2BB673),
    Color(0xFFFF8A3D), Color(0xFF00A7C4), Color(0xFFE0457B), Color(0xFF6C7A89),
  ];

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final m = message;
    final bg = mine ? color.primaryContainer : color.surfaceContainerHigh;
    final fg = mine ? color.onPrimaryContainer : color.onSurface;
    final meta = fg.withAlpha(150);
    final width = MediaQuery.sizeOf(context).width;
    final maxW = (width >= 900 ? (width - 380) : width) * (m.kind == MessageKind.text ? 0.78 : 0.86);
    const r = Radius.circular(18);
    const small = Radius.circular(5);
    final radius = BorderRadius.only(
      topLeft: r,
      topRight: r,
      bottomLeft: mine || !showTail ? r : small,
      bottomRight: mine && showTail ? small : r,
    );

    final time = Row(mainAxisSize: MainAxisSize.min, children: [
      if (m.edited && !m.deleted) Text('edited · ', style: TextStyle(fontSize: 10.5, color: meta, fontStyle: FontStyle.italic)),
      if (m.pinned) Padding(padding: const EdgeInsets.only(right: 3), child: Icon(Icons.push_pin_rounded, size: 11, color: meta)),
      Text(DateFormat.Hm().format(m.createdAt), style: TextStyle(fontSize: 10.5, color: meta)),
      if (mine) ...[const SizedBox(width: 3), DeliveryTicks(delivery, size: 14, color: meta)],
    ]);

    Widget content;
    if (m.deleted) {
      content = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block_rounded, size: 15, color: meta),
        const SizedBox(width: 6),
        Flexible(child: Text('This message was deleted', style: TextStyle(color: meta, fontStyle: FontStyle.italic))),
      ]);
    } else {
      content = switch (m.kind) {
        MessageKind.image => _ImageContent(m, fg: fg),
        MessageKind.note => _NoteContent(m, mine: mine),
        MessageKind.block => _BlockContent(m, mine: mine),
        _ => _TextContent(m.body, fg: fg),
      };
    }

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxW.clamp(220.0, 640.0).toDouble()),
      decoration: BoxDecoration(
        color: highlight ? Color.alphaBlend(color.primary.withAlpha(50), bg) : bg,
        borderRadius: radius,
        border: mine ? null : Border.all(color: color.outlineVariant.withAlpha(90)),
      ),
      padding: EdgeInsets.fromLTRB(m.kind == MessageKind.image ? 4 : 12, m.kind == MessageKind.image ? 4 : 8,
          m.kind == MessageKind.image ? 4 : 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (senderName != null)
            Padding(
              padding: EdgeInsets.only(bottom: 3, left: m.kind == MessageKind.image ? 8 : 0, top: m.kind == MessageKind.image ? 4 : 0),
              child: Text(senderName!,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: _names[(senderSeed ?? '').codeUnits.fold<int>(0, (a, b) => a + b) % _names.length])),
            ),
          if (m.replyTo != null && !m.deleted) _ReplyQuote(m.replyTo!, name: replyName ?? 'Message', mine: mine, onTap: onTapReply),
          content,
          const SizedBox(height: 2),
          Align(alignment: Alignment.bottomRight, widthFactor: 1, child: Padding(
            padding: EdgeInsets.only(right: m.kind == MessageKind.image ? 6 : 0, bottom: m.kind == MessageKind.image ? 2 : 0),
            child: time,
          )),
        ],
      ),
    );

    final reactions = _reactionSummary(m.reactions);

    return Padding(
      padding: EdgeInsets.only(top: showTail ? 2 : 1, bottom: reactions.isEmpty ? 1 : 0),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: m.isPending ? null : onLongPress,
            onSecondaryTap: m.isPending ? null : onLongPress,
            onTap: delivery == Delivery.failed ? onTapFailed : null,
            child: bubble,
          ),
          if (reactions.isNotEmpty)
            Transform.translate(
              offset: const Offset(0, -4),
              child: Wrap(
                spacing: 4,
                children: [
                  for (final r in reactions)
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: onReact == null ? null : () => onReact!(r.emoji),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: m.reactions[myId] == r.emoji ? color.primary.withAlpha(40) : color.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: m.reactions[myId] == r.emoji ? color.primary.withAlpha(140) : color.surface,
                            width: 1.5,
                          ),
                        ),
                        child: Text(r.count > 1 ? '${r.emoji} ${r.count}' : r.emoji, style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                ],
              ),
            ),
          if (delivery == Delivery.failed)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: Text('Not sent. Tap to try again.', style: TextStyle(fontSize: 11.5, color: color.error)),
            ),
        ],
      ),
    );
  }

  static List<({String emoji, int count})> _reactionSummary(Map<String, String> reactions) {
    final counts = <String, int>{};
    for (final e in reactions.values) {
      counts[e] = (counts[e] ?? 0) + 1;
    }
    final list = [for (final e in counts.entries) (emoji: e.key, count: e.value)];
    list.sort((a, b) => b.count.compareTo(a.count));
    return list;
  }
}

class _TextContent extends StatelessWidget {
  const _TextContent(this.text, {required this.fg});
  final String text;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: fg, fontSize: 15, height: 1.35);
    // Short messages of only emoji show bigger.
    final onlyEmoji = text.runes.length <= 6 && !RegExp(r'[A-Za-z0-9؀-ۿ]').hasMatch(text) && text.trim().isNotEmpty;
    if (onlyEmoji) return Text(text, style: style.copyWith(fontSize: 34, height: 1.2));
    return SelectableText.rich(
      linkifiedSpan(context, text, style: style),
      onTap: null,
    );
  }
}

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote(this.reply, {required this.name, required this.mine, this.onTap});
  final ReplyPreview reply;
  final String name;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: (mine ? color.onPrimaryContainer : color.primary).withAlpha(22),
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: color.primary, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: color.primary)),
          Text(reply.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: color.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _ImageContent extends StatelessWidget {
  const _ImageContent(this.m, {required this.fg});
  final ChatMessage m;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final url = m.imageUrl;
    final provider = url == null ? null : CachedNetworkImageProvider(url);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: GestureDetector(
          onTap: provider == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImagePreview(image: provider))),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340, minWidth: 160, minHeight: 120),
            child: url == null
                ? const SizedBox(width: 200, height: 160, child: Icon(Icons.broken_image_outlined))
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const SizedBox(width: 220, height: 180, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                    errorWidget: (_, __, ___) => const SizedBox(width: 220, height: 160, child: Center(child: Icon(Icons.broken_image_outlined))),
                  ),
          ),
        ),
      ),
      if (m.body.isNotEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(8, 6, 8, 0), child: _TextContent(m.body, fg: fg)),
    ]);
  }
}

/// A whole note in a message: title, what's in it, open and save.
class _NoteContent extends StatelessWidget {
  const _NoteContent(this.m, {required this.mine});
  final ChatMessage m;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final note = noteFromPayload(m.payload);
    if (note == null) return const Text('A note that can\'t be shown');
    final langs = note.blocks.whereType<CodeBlockEntity>().map((b) => languageInfo(b.language).short).toSet().take(4).toList();
    final firstText = note.blocks
        .where((b) => b is NoteBlockEntity || b is MarkdownBlockEntity)
        .map((b) => (b.text ?? '').trim())
        .firstWhere((t) => t.isNotEmpty, orElse: () => '');
    return SizedBox(
      width: 280,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.surface.withAlpha(mine ? 150 : 255),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.outlineVariant.withAlpha(140)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.description_rounded, size: 18, color: color.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(note.title.trim().isEmpty ? 'Untitled note' : note.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
            if (firstText.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(firstText, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: color.onSurfaceVariant, fontSize: 13)),
            ],
            const SizedBox(height: 8),
            Text(
              '// ${note.blocks.length} ${note.blocks.length == 1 ? 'block' : 'blocks'}${langs.isEmpty ? '' : ' · ${langs.join(' ')}'}',
              style: monoStyle(context, size: 11, color: tokens.subtle),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextButton.icon(
              onPressed: () => showNotePreview(context, m),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Preview'),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: () => openAsMyNote(context, m),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Save'),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// One block in a message: code with its language, copy and save.
class _BlockContent extends StatelessWidget {
  const _BlockContent(this.m, {required this.mine});
  final ChatMessage m;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = Theme.of(context).colorScheme;
    final block = blockFromPayload(m.payload);
    if (block == null) return const Text('A block that can\'t be shown');
    final code = block is CodeBlockEntity;
    final lang = code ? languageInfo(block.language) : null;
    final text = (block.text ?? '').trimRight();
    final lines = text.split('\n');
    final shown = lines.take(14).join('\n');
    return SizedBox(
      width: 320,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Container(
          decoration: BoxDecoration(color: code ? tokens.codeBackground : color.surface, borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
              color: Colors.black.withAlpha(30),
              child: Row(children: [
                Icon(code ? Icons.code_rounded : Icons.notes_rounded, size: 15, color: tokens.subtle),
                const SizedBox(width: 6),
                Expanded(child: Text(lang?.label ?? 'Text', style: monoStyle(context, size: 11.5, color: tokens.subtle))),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: text));
                    showSnack(context, 'Copied');
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(children: [
                      Icon(Icons.copy_rounded, size: 14, color: tokens.subtle),
                      const SizedBox(width: 4),
                      Text('copy', style: monoStyle(context, size: 11, color: tokens.subtle)),
                    ]),
                  ),
                ),
              ]),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Text(shown, style: monoStyle(context, size: 12.5).copyWith(height: 1.45)),
            ),
            if (lines.length > 14)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text('… ${lines.length - 14} more lines', style: monoStyle(context, size: 11, color: tokens.subtle)),
              ),
          ]),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => openAsMyNote(context, m),
            icon: Icon(code ? Icons.play_arrow_rounded : Icons.download_rounded, size: 18),
            label: Text(code ? 'Open as a note and run' : 'Save to my notes'),
          ),
        ),
      ]),
    );
  }
}

/// Read-only look at a note someone sent.
Future<void> showNotePreview(BuildContext context, ChatMessage m) {
  final note = noteFromPayload(m.payload);
  if (note == null) return Future.value();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) {
      final tokens = c.tokens;
      final color = Theme.of(c).colorScheme;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (c, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(note.title.trim().isEmpty ? 'Untitled note' : note.title,
                style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('// shared in chat · read only', style: monoStyle(c, size: 11, color: tokens.subtle)),
            const SizedBox(height: 16),
            for (final b in note.blocks)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: switch (b) {
                  CodeBlockEntity() => Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: tokens.codeBackground, borderRadius: BorderRadius.circular(AppBrand.radiusSmall)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(languageInfo(b.language).label, style: monoStyle(c, size: 11, color: tokens.subtle)),
                        const SizedBox(height: 6),
                        SelectableText(b.text ?? '', style: monoStyle(c, size: 12.5).copyWith(height: 1.45)),
                      ]),
                    ),
                  ImageBlockEntity() => (b.imagePath ?? '').startsWith('http')
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
                          child: CachedNetworkImage(imageUrl: b.imagePath!, fit: BoxFit.cover))
                      : const SizedBox.shrink(),
                  _ => SelectableText(b.text ?? '', style: TextStyle(color: color.onSurface, height: 1.45)),
                },
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(c);
                openAsMyNote(context, m);
              },
              icon: const Icon(Icons.download_rounded),
              label: const Text('Save to my notes and open'),
            ),
          ],
        ),
      );
    },
  );
}

/// The language name of a code block, for previews.
String blockLabel(BlockEntity b) => b is CodeBlockEntity ? languageInfo(b.language).label : 'Text';

/// Language from a payload's "Language.python" string, for the composer.
Language? payloadLanguage(Map<String, dynamic>? payload) {
  final raw = payload?['language'] as String?;
  if (raw == null) return null;
  return Language.values.where((l) => l.toString() == raw).firstOrNull;
}
