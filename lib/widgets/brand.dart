import 'package:flutter/material.dart';

import '../constants/themes.dart';

/// Small pieces that give CodeNote its "terminal" personality.

/// The CodeNote logo (the original app icon).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: Image.asset(
        'assets/logo/logo.png',
        width: size,
        height: size,
        semanticLabel: 'CodeNote',
      ),
    );
  }
}

/// A block cursor that blinks like a terminal's.
class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({super.key, this.width = 9, this.height = 16, this.color});
  final double width;
  final double height;
  final Color? color;

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1060),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.tokens.success;
    // Respect "reduce motion": a steady cursor instead of a blinking one.
    if (MediaQuery.of(context).disableAnimations) {
      return _block(color);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _controller.value < 0.5 ? 1 : 0,
        child: child,
      ),
      child: _block(color),
    );
  }

  Widget _block(Color color) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

/// A shell-style prompt line, for example `~/notes $ _`.
class PromptLine extends StatelessWidget {
  const PromptLine({
    super.key,
    required this.path,
    this.command,
    this.size = 14,
    this.showCursor = true,
  });

  final String path;
  final String? command;
  final double size;
  final bool showCursor;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: path,
                style: monoStyle(context,
                    size: size, weight: FontWeight.w700, color: color.primary),
              ),
              TextSpan(
                text: ' \$ ',
                style: monoStyle(context, size: size, color: context.tokens.subtle),
              ),
              if (command != null)
                TextSpan(
                  text: command,
                  style: monoStyle(context, size: size),
                ),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showCursor) ...[
          const SizedBox(width: 2),
          BlinkingCursor(width: size * 0.6, height: size * 1.15),
        ],
      ],
    );
  }
}

/// A section label written like a code comment: `// pinned  3`.
class CommentLabel extends StatelessWidget {
  const CommentLabel(this.text, {super.key, this.count, this.trailing});
  final String text;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final subtle = context.tokens.subtle;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
        child: Row(
          children: [
            Text('// ', style: monoStyle(context, size: 13, color: subtle)),
            Text(text,
                style: monoStyle(context,
                    size: 13,
                    weight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface)),
            if (count != null) ...[
              const SizedBox(width: 8),
              Text('$count', style: monoStyle(context, size: 12, color: subtle)),
            ],
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// An empty state that looks like a short terminal session.
class TerminalEmptyState extends StatelessWidget {
  const TerminalEmptyState({
    super.key,
    required this.command,
    required this.output,
    this.hint,
    this.action,
  });

  /// What the "user" typed, for example `ls ~/notes`.
  final String command;

  /// What the "terminal" answered.
  final String output;

  /// One friendly line under the terminal.
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: tokens.codeBackground,
                  borderRadius: BorderRadius.circular(AppBrand.radius),
                  border: Border.all(color: color.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _WindowDots(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(TextSpan(children: [
                            TextSpan(
                                text: '\$ ',
                                style: monoStyle(context, color: tokens.success)),
                            TextSpan(text: command, style: monoStyle(context)),
                          ])),
                          const SizedBox(height: 6),
                          Text(output,
                              style: monoStyle(context, color: tokens.subtle)),
                          const SizedBox(height: 6),
                          Row(children: [
                            Text('\$ ',
                                style: monoStyle(context, color: tokens.success)),
                            const BlinkingCursor(width: 8, height: 15),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 16),
                Text(
                  hint!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: tokens.subtle),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 16),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The three dots at the top of a terminal or editor window.
class _WindowDots extends StatelessWidget {
  const _WindowDots();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c) => Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(children: [
        dot(const Color(0xFFFF6B6B)),
        dot(AppBrand.amber),
        dot(AppBrand.mint),
      ]),
    );
  }
}

/// A terminal-looking window with any content inside. Used by onboarding.
class TerminalWindow extends StatelessWidget {
  const TerminalWindow({super.key, required this.child, this.title});
  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: context.tokens.codeBackground,
        borderRadius: BorderRadius.circular(AppBrand.radius),
        border: Border.all(color: color.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: AppBrand.violet.withAlpha(40),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const _WindowDots(),
            if (title != null)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 40),
                  child: Text(title!,
                      textAlign: TextAlign.center,
                      style: monoStyle(context,
                          size: 11, color: context.tokens.subtle)),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }
}
