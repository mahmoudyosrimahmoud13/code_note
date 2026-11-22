import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/themes.dart';
import '../backend/backend.dart';
import '../models.dart';

/// A round picture, or initials on a color picked from the id.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.seed, required this.name, this.imageUrl, this.size = 44, this.online = false,
      this.group = false});

  factory Avatar.profile(Profile p, {double size = 44, bool online = false, Key? key}) =>
      Avatar(key: key, seed: p.id, name: p.isDeleted ? '?' : p.name, imageUrl: p.isDeleted ? null : p.avatarUrl, size: size, online: online);

  factory Avatar.chat(Chat c, {double size = 48, bool online = false, Key? key}) => c.isGroup
      ? Avatar(key: key, seed: c.id, name: c.name, imageUrl: c.imageUrl, size: size, group: true)
      : Avatar(key: key, seed: c.otherUser?.id ?? c.id, name: c.name, imageUrl: c.imageUrl, size: size, online: online);

  final String seed;
  final String name;
  final String? imageUrl;
  final double size;
  final bool online;
  final bool group;

  static const _palette = [
    Color(0xFF7B5CFF), Color(0xFF3D7BFF), Color(0xFFD45CF0), Color(0xFF2BB673),
    Color(0xFFFF8A3D), Color(0xFF00A7C4), Color(0xFFE0457B), Color(0xFF6C7A89),
  ];

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    return (parts.length == 1 ? first : first + parts.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = _palette[seed.codeUnits.fold<int>(0, (a, b) => a + b) % _palette.length];
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, Color.lerp(color, Colors.black, 0.25)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: group && name.trim().isEmpty
          ? Icon(Icons.groups_rounded, color: Colors.white, size: size * 0.5)
          : Text(_initials,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.38, height: 1)),
    );
    final image = imageUrl == null
        ? fallback
        : CachedNetworkImage(
            imageUrl: imageUrl!,
            fit: BoxFit.cover,
            memCacheWidth: (size * 3).round(),
            placeholder: (_, __) => fallback,
            errorWidget: (_, __, ___) => fallback,
          );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(size * (group ? 0.3 : 0.5)), child: SizedBox.expand(child: image)),
          if (online)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.3,
                height: size * 0.3,
                decoration: BoxDecoration(
                  color: AppBrand.mint,
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "14:05" today, "Yesterday", "Mon", or "Nov 3".
String chatTime(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return DateFormat.Hm().format(t);
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return DateFormat.E().format(t);
  if (t.year == now.year) return DateFormat.MMMd().format(t);
  return DateFormat.yMMMd().format(t);
}

/// "Today", "Yesterday", "Monday, Nov 3".
String dayLabel(DateTime t) {
  final now = DateTime.now();
  final diff = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (t.year == now.year) return DateFormat('EEEE, MMM d').format(t);
  return DateFormat.yMMMMd().format(t);
}

/// "online", "last seen 5 min ago", "last seen yesterday at 21:04".
String lastSeenLabel(bool online, DateTime? seen) {
  if (online) return 'online';
  if (seen == null) return 'last seen a while ago';
  final d = DateTime.now().difference(seen);
  if (d.inMinutes < 1) return 'last seen just now';
  if (d.inMinutes < 60) return 'last seen ${d.inMinutes} min ago';
  if (d.inHours < 24 && DateTime.now().day == seen.day) return 'last seen today at ${DateFormat.Hm().format(seen)}';
  if (d.inDays < 2) return 'last seen yesterday at ${DateFormat.Hm().format(seen)}';
  return 'last seen ${DateFormat.MMMd().format(seen)}';
}

/// The little marks after my own messages.
class DeliveryTicks extends StatelessWidget {
  const DeliveryTicks(this.delivery, {super.key, this.color, this.size = 15});
  final Delivery delivery;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final base = color ?? context.tokens.subtle;
    return switch (delivery) {
      Delivery.sending => Icon(Icons.schedule_rounded, size: size - 2, color: base, semanticLabel: 'Sending'),
      Delivery.failed => Icon(Icons.error_outline_rounded, size: size, color: Theme.of(context).colorScheme.error, semanticLabel: 'Not sent'),
      Delivery.sent => Icon(Icons.done_rounded, size: size, color: base, semanticLabel: 'Sent'),
      Delivery.delivered => Icon(Icons.done_all_rounded, size: size, color: base, semanticLabel: 'Delivered'),
      Delivery.seen => Icon(Icons.done_all_rounded, size: size, color: AppBrand.blue, semanticLabel: 'Seen'),
    };
  }
}

/// A short message at the bottom; errors in the error color.
void showSnack(BuildContext context, Object message, {bool error = false}) {
  final text = message is ApiError ? message.message : '$message';
  final color = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: error ? color.error : null,
      content: Text(text, style: error ? TextStyle(color: color.onError) : null),
    ));
}

/// Runs [work], showing what went wrong if it fails. True if it worked.
Future<bool> attempt(BuildContext context, Future<void> Function() work, {String? done}) async {
  try {
    await work();
    if (done != null && context.mounted) showSnack(context, done);
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, e is ApiError ? e.message : 'Something went wrong: $e', error: true);
    return false;
  }
}

/// A "// label" section title, the CodeNote way.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 8), this.trailing});
  final String text;
  final EdgeInsets padding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(
              child: Text('// ${text.toLowerCase()}',
                  style: monoStyle(context, size: 12, weight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// A card-like group of rows, like Settings.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.children, this.margin = const EdgeInsets.symmetric(horizontal: 16)});
  final List<Widget> children;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppBrand.radius),
        border: Border.all(color: color.outlineVariant.withAlpha(160)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 16, endIndent: 16, color: color.outlineVariant.withAlpha(120)),
          children[i],
        ],
      ]),
    );
  }
}

/// Asks before something that can't be undone.
Future<bool> confirm(BuildContext context, {required String title, required String body, required String action,
    bool danger = true}) async {
  final color = Theme.of(context).colorScheme;
  return await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
              style: danger ? FilledButton.styleFrom(backgroundColor: color.error, foregroundColor: color.onError) : null,
              onPressed: () => Navigator.pop(c, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
}

/// The empty state of a list: an icon, a line and an optional button.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action});
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: color.primary.withAlpha(24), borderRadius: BorderRadius.circular(22)),
              child: Icon(icon, size: 34, color: color.primary),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (body != null) ...[
              const SizedBox(height: 6),
              Text(body!, textAlign: TextAlign.center, style: TextStyle(color: color.onSurfaceVariant, height: 1.4)),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}
