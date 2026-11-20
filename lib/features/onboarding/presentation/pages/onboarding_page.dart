import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../constants/themes.dart';
import '../../../../widgets/brand.dart';
import '../../sample_notes.dart';
import '../../../settings/presentation/bloc/settings_bloc.dart';
import '../../../settings/presentation/bloc/settings_event.dart';
import '../../../settings/presentation/bloc/settings_state.dart';

/// First-run tour. Each page is a small terminal "scene" drawn in code,
/// so it matches the app in light and dark mode and needs no images.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _page = 0;

  static const _pages = <_Page>[
    _Page(
      title: 'Hello, CodeNote',
      body: 'A notebook for code, notes and ideas. Text, code, markdown and images, all in one note.',
      scene: _Scene.welcome,
    ),
    _Page(
      title: 'Real code blocks',
      body: 'Syntax highlighting for 20+ languages, a real code font, and quick keys for the symbols phones hide.',
      scene: _Scene.code,
    ),
    _Page(
      title: 'Keep it organized',
      body: 'Group notes into folders, tag them, pin the important ones, and find anything with search.',
      scene: _Scene.organize,
    ),
    _Page(
      title: 'Yours, on this device',
      body: 'The Community Edition is local-only. No account, no cloud, no tracking.',
      scene: _Scene.private,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _finish() {
    _addDemoContent();
    final bloc = context.read<SettingsBloc>();
    final state = bloc.state;
    if (state is SettingsLoaded) {
      bloc.add(UpdateSettingsEvent(
          state.settings.copyWith(hasCompletedOnboarding: true)));
    }
  }

  /// First launch only: add sample notes and folders, unless notes already
  /// exist (for example after updating from an older version).
  void _addDemoContent() => addSampleNotes(context, onlyIfEmpty: true);

  void _next() {
    if (_page == _pages.length - 1) {
      _finish();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final last = _page == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                  child: Row(
                    children: [
                      const BrandMark(size: 28),
                      const SizedBox(width: 10),
                      Text('codenote',
                          style: monoStyle(context,
                              size: 15, weight: FontWeight.w700)),
                      const Spacer(),
                      if (!last)
                        TextButton(onPressed: _finish, child: const Text('Skip')),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) {
                      final page = _pages[i];
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                        child: Column(
                          children: [
                            // Rebuilt when the page shows, so it animates each time.
                            _SceneView(
                              key: ValueKey('scene_${i}_${_page == i}'),
                              scene: page.scene,
                              active: _page == i,
                            ),
                            const SizedBox(height: 36),
                            Text(page.title,
                                textAlign: TextAlign.center,
                                style: text.headlineMedium),
                            const SizedBox(height: 12),
                            Text(
                              page.body,
                              textAlign: TextAlign.center,
                              style: text.bodyLarge
                                  ?.copyWith(color: color.onSurfaceVariant),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Row(
                    children: [
                      Semantics(
                        label: 'Page ${_page + 1} of ${_pages.length}',
                        child: Row(
                          children: [
                            for (var i = 0; i < _pages.length; i++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                margin: const EdgeInsets.only(right: 6),
                                height: 8,
                                width: _page == i ? 24 : 8,
                                decoration: BoxDecoration(
                                  color: _page == i
                                      ? color.primary
                                      : color.outlineVariant,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _next,
                        child: Text(last ? 'Start writing' : 'Next'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _Scene { welcome, code, organize, private }

class _Page {
  const _Page({required this.title, required this.body, required this.scene});
  final String title;
  final String body;
  final _Scene scene;
}

/// One styled piece of a terminal line.
class _Part {
  const _Part(this.text, [this.kind = _Kind.plain]);
  final String text;
  final _Kind kind;
}

enum _Kind { plain, prompt, subtle, ok, accent, keyword, string, number }

class _SceneView extends StatefulWidget {
  const _SceneView({super.key, required this.scene, required this.active});
  final _Scene scene;
  final bool active;

  @override
  State<_SceneView> createState() => _SceneViewState();
}

class _SceneViewState extends State<_SceneView> {
  int _shown = 0;
  Timer? _timer;

  List<List<_Part>> get _lines {
    switch (widget.scene) {
      case _Scene.welcome:
        return const [
          [_Part('\$ ', _Kind.prompt), _Part('codenote init')],
          [_Part('creating ~/notes ...', _Kind.subtle)],
          [_Part('✔ ', _Kind.ok), _Part('workspace ready')],
          [_Part('\$ ', _Kind.prompt), _Part('echo "let\'s write"')],
          [_Part("let's write", _Kind.accent)],
        ];
      case _Scene.code:
        return const [
          [_Part('# python', _Kind.subtle)],
          [_Part('def ', _Kind.keyword), _Part('greet'), _Part('(name):')],
          [
            _Part('    return ', _Kind.keyword),
            _Part('f"hi, {name}!"', _Kind.string)
          ],
          [_Part('')],
          [_Part('print', _Kind.accent), _Part('(greet('), _Part('"codenote"', _Kind.string), _Part('))')],
          [_Part('# → hi, codenote!', _Kind.subtle)],
        ];
      case _Scene.organize:
        return const [
          [_Part('\$ ', _Kind.prompt), _Part('tree ~/notes')],
          [_Part('├─ '), _Part('flutter/', _Kind.accent), _Part('   3 notes', _Kind.subtle)],
          [_Part('├─ '), _Part('python/', _Kind.accent), _Part('    5 notes', _Kind.subtle)],
          [_Part('├─ '), _Part('📌 ', _Kind.plain), _Part('deploy-checklist')],
          [_Part('└─ '), _Part('#sql #interview', _Kind.keyword)],
        ];
      case _Scene.private:
        return const [
          [_Part('\$ ', _Kind.prompt), _Part('codenote whereis my-notes')],
          [_Part('→ this device only', _Kind.ok)],
          [_Part('\$ ', _Kind.prompt), _Part('codenote upload')],
          [_Part('nope. local-only edition.', _Kind.subtle)],
          [_Part('✔ ', _Kind.ok), _Part('no account · no cloud · no tracking')],
        ];
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  void _start() {
    final reduceMotion =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (reduceMotion) {
      _shown = _lines.length;
      return;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 420), (t) {
      if (!mounted || _shown >= _lines.length) {
        t.cancel();
        return;
      }
      setState(() => _shown++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Color _colorFor(_Kind kind, BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    return switch (kind) {
      _Kind.plain => color.onSurface,
      _Kind.prompt => tokens.success,
      _Kind.subtle => tokens.subtle,
      _Kind.ok => tokens.success,
      _Kind.accent => color.primary,
      _Kind.keyword => AppBrand.magenta,
      _Kind.string => tokens.pin,
      _Kind.number => AppBrand.blue,
    };
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    final title = switch (widget.scene) {
      _Scene.welcome => 'zsh — ~',
      _Scene.code => 'greet.py',
      _Scene.organize => 'zsh — ~/notes',
      _Scene.private => 'zsh — privacy',
    };

    return ExcludeSemantics(
      child: TerminalWindow(
        title: title,
        child: SizedBox(
          height: 150,
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lines.length; i++)
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: i < _shown ? 1 : 0,
                  child: Text.rich(
                    TextSpan(children: [
                      for (final part in lines[i])
                        TextSpan(
                          text: part.text,
                          style: monoStyle(context,
                              size: 13, color: _colorFor(part.kind, context)),
                        ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                  ),
                ),
              if (_shown >= lines.length)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: BlinkingCursor(width: 8, height: 15),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
