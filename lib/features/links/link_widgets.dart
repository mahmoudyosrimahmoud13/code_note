import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/themes.dart';
import 'link_preview.dart';

/// The look of a link inside text.
TextStyle linkStyle(BuildContext context, TextStyle? base) {
  final color = Theme.of(context).colorScheme.primary;
  return (base ?? const TextStyle()).copyWith(
    color: color,
    decoration: TextDecoration.underline,
    decorationColor: color.withAlpha(140),
  );
}

/// [text] with its links colored and underlined (not tappable).
TextSpan linkifiedSpan(BuildContext context, String text, {TextStyle? style}) {
  final ranges = LinkFinder.ranges(text);
  if (ranges.isEmpty) return TextSpan(text: text, style: style);
  final link = linkStyle(context, style);
  final children = <TextSpan>[];
  var at = 0;
  for (final r in ranges) {
    if (r.start > at) children.add(TextSpan(text: text.substring(at, r.start)));
    children.add(TextSpan(text: r.textInside(text), style: link));
    at = r.end;
  }
  if (at < text.length) children.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: style, children: children);
}

/// A text field controller that highlights links while you type.
class LinkTextController extends TextEditingController {
  LinkTextController({super.text});

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final text = value.text;
    final links = LinkFinder.ranges(text);
    if (links.isEmpty) return super.buildTextSpan(context: context, style: style, withComposing: withComposing);

    final composing = withComposing && value.isComposingRangeValid ? value.composing : null;
    final link = linkStyle(context, style);
    // Cut the text wherever a link or the word being typed starts or ends.
    final cuts = <int>{0, text.length};
    for (final r in links) {
      cuts..add(r.start)..add(r.end);
    }
    if (composing != null) cuts..add(composing.start)..add(composing.end);
    final points = cuts.toList()..sort();

    final children = <TextSpan>[];
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i], b = points[i + 1];
      if (a >= b) continue;
      final inLink = links.any((r) => a >= r.start && b <= r.end);
      final inComposing = composing != null && a >= composing.start && b <= composing.end;
      var s = inLink ? link : null;
      if (inComposing) {
        s = (s ?? const TextStyle()).copyWith(decoration: TextDecoration.underline);
      }
      children.add(TextSpan(text: text.substring(a, b), style: s));
    }
    return TextSpan(style: style, children: children);
  }
}

Future<void> openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't open $url"), persist: false));
  }
}

/// Preview cards for the links in [text] (three at most).
class LinkPreviewList extends StatelessWidget {
  const LinkPreviewList({super.key, required this.text, this.max = 3});
  final String text;
  final int max;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LinkPreviewService.instance,
      builder: (context, _) {
        if (!LinkPreviewService.instance.enabled) return const SizedBox.shrink();
        final urls = LinkFinder.urls(text).take(max).toList();
        if (urls.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final url in urls)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LinkPreviewCard(key: ValueKey(url), url: url),
              ),
          ],
        );
      },
    );
  }
}

/// A card with the page's picture, title, description and site.
/// [compact] is the small version used on note cards in the home screen:
/// it doesn't react to taps, so tapping it opens the note.
class LinkPreviewCard extends StatefulWidget {
  const LinkPreviewCard({super.key, required this.url, this.compact = false});
  final String url;
  final bool compact;

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  late Future<LinkPreview?> _future;

  @override
  void initState() {
    super.initState();
    _future = LinkPreviewService.instance.get(widget.url);
  }

  @override
  void didUpdateWidget(LinkPreviewCard old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _future = LinkPreviewService.instance.get(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LinkPreview?>(
      future: _future,
      initialData: LinkPreviewService.instance.cached(widget.url),
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done && snap.data == null;
        final card = _card(context, snap.data, loading);
        if (widget.compact) return IgnorePointer(child: card);
        return Semantics(
          link: true,
          label: 'Link: ${snap.data?.title ?? widget.url}',
          child: card,
        );
      },
    );
  }

  Widget _card(BuildContext context, LinkPreview? p, bool loading) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final compact = widget.compact;
    final domain = LinkFinder.domain(widget.url);
    final title = p?.title ?? (loading ? null : widget.url);
    final thumb = compact ? 44.0 : 88.0;
    final image = p?.image;

    Widget picture() => ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 6 : 8),
          child: SizedBox(
            width: thumb,
            height: thumb,
            child: image == null
                ? Container(
                    color: color.primary.withAlpha(22),
                    child: Icon(Icons.link_rounded, color: color.primary, size: compact ? 18 : 26),
                  )
                : CachedNetworkImage(
                    imageUrl: image,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 120),
                    memCacheWidth: (thumb * 3).round(),
                    placeholder: (_, __) => Container(color: color.surfaceContainerHighest),
                    errorWidget: (_, __, ___) => Container(
                      color: color.primary.withAlpha(22),
                      child: Icon(Icons.link_rounded, color: color.primary, size: compact ? 18 : 26),
                    ),
                  ),
          ),
        );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Text(
            title,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: (compact ? textTheme.labelMedium : textTheme.titleSmall)
                ?.copyWith(color: color.onSurface, fontWeight: FontWeight.w600),
          )
        else
          Container(
            height: 12,
            width: 140,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: color.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        if (!compact && (p?.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            p!.description!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(color: color.onSurfaceVariant, height: 1.35),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          p?.site != null && !compact ? '${p!.site} · $domain' : domain,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: monoStyle(context, size: compact ? 10 : 11, color: tokens.subtle),
        ),
      ],
    );

    final content = Padding(
      padding: EdgeInsets.all(compact ? 6 : 8),
      child: Row(
        children: [
          picture(),
          SizedBox(width: compact ? 8 : 12),
          Expanded(child: body),
          if (!compact)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.open_in_new_rounded, size: 16, color: tokens.subtle),
            ),
        ],
      ),
    );

    return Material(
      color: compact ? color.surfaceContainer : color.surfaceContainerLow,
      borderRadius: BorderRadius.circular(compact ? AppBrand.radiusSmall - 4 : AppBrand.radiusSmall),
      clipBehavior: Clip.antiAlias,
      child: compact
          ? content
          : InkWell(
              onTap: () => openLink(context, widget.url),
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: widget.url));
                HapticFeedback.selectionClick();
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copied'), persist: false));
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: color.outlineVariant.withAlpha(160)),
                  borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
                ),
                child: content,
              ),
            ),
    );
  }
}
