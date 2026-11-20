import 'package:flutter/material.dart';

import '../../constants/themes.dart';

/// One styled piece of a preview line.
class MdSegment {
  const MdSegment(this.text, {this.bold = false, this.italic = false, this.code = false, this.link = false});
  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final bool link;

  @override
  String toString() => text;
}

/// One line of the preview. [heading] is 1-6 for # to ######, 0 otherwise.
class MdLine {
  const MdLine(this.segments, {this.heading = 0, this.codeBlock = false, this.quote = false});
  final List<MdSegment> segments;
  final int heading;
  final bool codeBlock;
  final bool quote;

  String get plain => segments.map((s) => s.text).join();
}

/// Turns Markdown into short styled lines for note cards and folder
/// previews: no raw `#`, `**` or `[link](url)`, just what a reader sees.
/// Deliberately small and fast; the note page uses the full renderer.
class MarkdownPreview {
  MarkdownPreview._();

  static final _inline = RegExp(
    r'(`[^`]+`)'                // `code`
    r'|(\*\*[^*]+\*\*)'         // **bold**
    r'|(__[^_]+__)'             // __bold__
    r'|(~~[^~]+~~)'             // ~~strike~~ (shown as plain text)
    r'|(\*[^*\s][^*]*\*)'       // *italic*
    r'|(!\[[^\]]*\]\([^)]*\))'  // ![image](url) (dropped)
    r'|(\[[^\]]+\]\([^)]*\))',  // [text](url)
  );

  static List<MdSegment> inline(String text) {
    final out = <MdSegment>[];
    var last = 0;
    for (final m in _inline.allMatches(text)) {
      if (m.start > last) out.add(MdSegment(text.substring(last, m.start)));
      final t = m.group(0)!;
      if (m.group(1) != null) {
        out.add(MdSegment(t.substring(1, t.length - 1), code: true));
      } else if (m.group(2) != null || m.group(3) != null) {
        out.add(MdSegment(t.substring(2, t.length - 2), bold: true));
      } else if (m.group(4) != null) {
        out.add(MdSegment(t.substring(2, t.length - 2)));
      } else if (m.group(5) != null) {
        out.add(MdSegment(t.substring(1, t.length - 1), italic: true));
      } else if (m.group(6) != null) {
        // images: nothing to show in a text preview
      } else {
        out.add(MdSegment(t.substring(1, t.indexOf('](')), link: true));
      }
      last = m.end;
    }
    if (last < text.length) out.add(MdSegment(text.substring(last)));
    return out;
  }

  /// The first [maxLines] visible lines of [markdown].
  static List<MdLine> parse(String markdown, {int maxLines = 12}) {
    final lines = <MdLine>[];
    var inFence = false;
    for (final raw in markdown.split('\n')) {
      if (lines.length >= maxLines) break;
      final line = raw.trimRight();
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        inFence = !inFence;
        continue;
      }
      if (inFence) {
        lines.add(MdLine([MdSegment(line, code: true)], codeBlock: true));
        continue;
      }
      if (trimmed.isEmpty) continue;
      if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) continue;
      // Table separator rows like |---|:--:|
      if (RegExp(r'^\|?[\s:\-|]+\|[\s:\-|]*$').hasMatch(trimmed)) continue;

      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        lines.add(MdLine(inline(heading.group(2)!), heading: heading.group(1)!.length));
        continue;
      }
      final quote = RegExp(r'^>\s?(.*)$').firstMatch(trimmed);
      if (quote != null) {
        lines.add(MdLine(inline(quote.group(1)!), quote: true));
        continue;
      }
      final task = RegExp(r'^[-*+]\s+\[([ xX])\]\s+(.*)$').firstMatch(trimmed);
      if (task != null) {
        final done = task.group(1)!.toLowerCase() == 'x';
        lines.add(MdLine([MdSegment(done ? '☑ ' : '☐ '), ...inline(task.group(2)!)]));
        continue;
      }
      final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(trimmed);
      if (bullet != null) {
        final indent = (line.length - trimmed.length) >= 2 ? '   ' : '';
        lines.add(MdLine([MdSegment('$indent• '), ...inline(bullet.group(1)!)]));
        continue;
      }
      final numbered = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(trimmed);
      if (numbered != null) {
        lines.add(MdLine([MdSegment('${numbered.group(1)}. '), ...inline(numbered.group(2)!)]));
        continue;
      }
      if (trimmed.startsWith('|')) {
        final cells = trimmed
            .split('|')
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .join('   ');
        lines.add(MdLine(inline(cells)));
        continue;
      }
      lines.add(MdLine(inline(trimmed)));
    }
    return lines;
  }
}

/// Renders [markdown] as a compact, styled preview.
class MarkdownPreviewText extends StatelessWidget {
  const MarkdownPreviewText(
    this.markdown, {
    super.key,
    this.maxLines = 5,
    this.fontSize = 12.5,
    this.color,
  });

  final String markdown;
  final int maxLines;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final base = TextStyle(
      fontSize: fontSize,
      height: 1.45,
      color: color ?? scheme.onSurfaceVariant,
    );
    final lines = MarkdownPreview.parse(markdown, maxLines: maxLines + 2);
    final spans = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      var lineStyle = base;
      if (line.heading > 0) {
        lineStyle = base.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
          fontSize: fontSize + (line.heading <= 2 ? 1.5 : 0.5),
        );
      } else if (line.quote) {
        lineStyle = base.copyWith(fontStyle: FontStyle.italic);
        spans.add(TextSpan(text: '▍', style: base.copyWith(color: scheme.primary)));
      } else if (line.codeBlock) {
        lineStyle = monoStyle(context, size: fontSize - 1, color: tokens.success).copyWith(height: 1.45);
      }
      for (final s in line.segments) {
        var st = lineStyle;
        if (s.bold) st = st.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface);
        if (s.italic) st = st.copyWith(fontStyle: FontStyle.italic);
        if (s.link) st = st.copyWith(color: scheme.primary);
        if (s.code) {
          st = monoStyle(context, size: fontSize - 1, color: scheme.primary)
              .copyWith(height: 1.45, backgroundColor: scheme.primary.withAlpha(22));
        }
        spans.add(TextSpan(text: s.text, style: st));
      }
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
