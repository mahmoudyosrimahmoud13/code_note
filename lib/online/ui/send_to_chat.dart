import 'package:flutter/material.dart';

import '../../features/notes/domain/entities/note.dart';
import '../../helpers/helper_methods.dart';
import '../chat/chat_store.dart';
import '../models.dart';
import '../online_service.dart';
import 'auth_pages.dart';
import 'common.dart';
import 'conversation_page.dart';
import 'message_widgets.dart';

/// From a note's ⋮ menu: pick a chat and send the note there.
Future<void> sendNoteToChat(BuildContext context, NoteEntity note) async {
  if (!OnlineService.instance.signedIn) {
    showSnack(context, 'Sign in to send notes in chats.');
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthPage()));
    return;
  }
  final store = ChatStore.instance;
  if (!store.loaded) await store.refresh();
  if (!context.mounted) return;
  final chat = await showModalBottomSheet<Chat>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (c, scroll) => ListView(controller: scroll, children: [
        SectionLabel('send "${note.title.trim().isEmpty ? 'Untitled' : note.title}" to', padding: const EdgeInsets.fromLTRB(20, 0, 20, 8)),
        if (store.chats.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No chats yet. Start one from Chats.'))),
        for (final ch in store.chats.where((x) => x.canSend))
          ListTile(
            leading: Avatar.chat(ch, size: 42),
            title: Text(ch.name),
            subtitle: Text(ch.isGroup ? '${ch.memberCount} members' : (ch.otherUser?.handle ?? '')),
            onTap: () => Navigator.pop(c, ch),
          ),
      ]),
    ),
  );
  if (chat == null || !context.mounted) return;
  final ok = await attempt(context, () async {
    final ready = await prepareNoteForSending(note);
    await store.thread(chat.id).send(kind: MessageKind.note, body: note.title, payload: notePayload(ready));
  });
  if (ok && context.mounted) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Sent to ${chat.name}'),
        action: SnackBarAction(
          label: 'Open chat',
          onPressed: () => navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => ConversationPage(chatId: chat.id))),
        ),
      ));
  }
}
