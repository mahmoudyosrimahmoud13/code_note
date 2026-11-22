import 'dart:async';

import 'package:flutter/material.dart';

import '../../helpers/helper_methods.dart';
import '../../widgets/brand.dart';
import '../chat/chat_store.dart';
import '../models.dart';
import '../online_service.dart';
import '../push/push_service.dart';
import 'auth_pages.dart';
import 'chats_page.dart';
import 'common.dart';
import 'conversation_page.dart';

/// Picks the first screen: the server address (FastAPI build), sign-in,
/// the email code, or the app itself ([child]).
class OnlineGate extends StatefulWidget {
  const OnlineGate({super.key, required this.child});
  final Widget child;

  @override
  State<OnlineGate> createState() => _OnlineGateState();
}

class _OnlineGateState extends State<OnlineGate> {
  @override
  void initState() {
    super.initState();
    PushService.instance.onOpenChat = _openChat;
    OnlineService.instance.addListener(_stageChanged);
  }

  @override
  void dispose() {
    OnlineService.instance.removeListener(_stageChanged);
    super.dispose();
  }

  void _stageChanged() {
    final online = OnlineService.instance;
    // Signing in from a page pushed on top (after "use without an account"):
    // go back to the start so the right screen shows.
    if (online.stage == OnlineStage.signedIn || online.stage == OnlineStage.needsEmailCode) {
      final nav = navigatorKey.currentState;
      if (nav != null && nav.canPop()) nav.popUntil((r) => r.isFirst);
    }
    if (online.stage == OnlineStage.signedIn) {
      final pending = PushService.instance.takePendingOpen();
      if (pending != null) Timer(const Duration(milliseconds: 400), () => _openChat(pending));
    }
  }

  void _openChat(String chatId) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !OnlineService.instance.signedIn) {
      return;
    }
    navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => ConversationPage(chatId: chatId)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OnlineService.instance,
      builder: (context, _) {
        final online = OnlineService.instance;
        switch (online.stage) {
          case OnlineStage.loading:
            return const Scaffold(body: Center(child: BrandMark(size: 64)));
          case OnlineStage.needsServer:
            return online.skipped ? widget.child : const ServerAddressPage();
          case OnlineStage.signedOut:
            return online.skipped ? widget.child : const AuthPage();
          case OnlineStage.needsEmailCode:
            return const EmailCodePage();
          case OnlineStage.signedIn:
            return widget.child;
        }
      },
    );
  }
}

/// A small card that slides in at the top for new messages while you're
/// elsewhere in the app. Tap to open the chat.
class IncomingBanner extends StatefulWidget {
  const IncomingBanner({super.key});

  @override
  State<IncomingBanner> createState() => _IncomingBannerState();
}

class _IncomingBannerState extends State<IncomingBanner> {
  ({Chat chat, ChatMessage message})? _current;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    ChatStore.instance.onIncoming = (chat, m) {
      _hide?.cancel();
      setState(() => _current = (chat: chat, message: m));
      _hide = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _current = null);
      });
    };
  }

  @override
  void dispose() {
    _hide?.cancel();
    ChatStore.instance.onIncoming = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _current;
    final color = Theme.of(context).colorScheme;
    return AnimatedSlide(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      offset: c == null ? const Offset(0, -1.6) : Offset.zero,
      child: c == null
          ? const SizedBox.shrink()
          : SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(18),
                    color: color.surfaceContainerHigh,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        setState(() => _current = null);
                        navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => ConversationPage(chatId: c.chat.id)));
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            Avatar.chat(c.chat, size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                Text(c.chat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text(
                                  c.chat.isGroup
                                      ? '${ChatStore.instance.thread(c.chat.id).member(c.message.senderId)?.name.split(' ').first ?? 'Someone'}: ${c.message.preview}'
                                      : c.message.preview,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: color.onSurfaceVariant),
                                ),
                              ]),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => setState(() => _current = null),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// The "Chats" button with the unread count, for the home screen.
class ChatsButton extends StatelessWidget {
  const ChatsButton({super.key, this.dense = false});
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ChatStore.instance,
      builder: (context, _) {
        final n = ChatStore.instance.totalUnread;
        return IconButton(
          visualDensity: dense ? VisualDensity.compact : null,
          tooltip: n > 0 ? 'Chats ($n unread)' : 'Chats',
          onPressed: () => ChatsPage.open(context),
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text(n > 99 ? '99+' : '$n'),
            child: const Icon(Icons.forum_outlined),
          ),
        );
      },
    );
  }
}
