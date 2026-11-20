import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../constants/themes.dart';
import 'runtimes.dart';
import 'runtimes_page.dart';
import 'sandbox.dart';
import 'sandbox_files_sheet.dart';

/// A shell inside the sandbox. Opened from a code block it starts in that
/// folder's sandbox, otherwise in the Terminal's own sandbox folder.
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, this.folder});
  final Directory? folder;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  static const _marker = '__CODENOTE_PWD__';

  final _lines = <String>[];
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _history = <String>[];
  int _historyPos = 0;

  Directory? _home;
  String _cwd = '';
  RunningProcess? _shell;
  StreamSubscription<String>? _sub;
  String? _problem;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _shell?.stop();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final allowed = await Sandbox.instance.canRun();
    if (allowed != true) {
      setState(() => _problem = allowed == null
          ? 'The terminal is off on this computer until you allow it in Settings > Runtimes and sandbox.'
          : "A terminal isn't available on this device.");
      return;
    }
    final shell = await Runtimes.instance.shell();
    if (shell == null) {
      setState(() => _problem = 'No shell yet. Download Bash in Settings > Runtimes and sandbox.');
      return;
    }
    final home = widget.folder ?? await Sandbox.instance.terminalHome();
    final (exe, pre) = shell;
    try {
      final proc = await Runtimes.instance.start(exe, [...pre], workDir: home);
      _sub = proc.lines.listen(_onLine, onDone: () {
        if (!mounted || _shell != proc) return;
        setState(() {
          _lines.add('${RunningProcess.errorMark}[the shell closed. Press Restart shell to start a new one]');
          _shell = null;
          _busy = false;
        });
      });
      setState(() {
        _home = home;
        _cwd = home.path;
        _shell = proc;
        _problem = null;
        _lines.add('CodeNote terminal · sandbox: ${p.basename(home.path)}');
        _lines.add('Files made here stay in the sandbox. Save copies from the folder button.');
        _lines.add('Try: python --version, pip install yt-dlp, ls, cat file.txt');
      });
    } on RuntimeException catch (e) {
      setState(() => _problem = e.message);
    }
  }

  void _onLine(String line) {
    if (!mounted) return;
    final clean = line.startsWith(RunningProcess.errorMark) ? line.substring(1) : line;
    if (clean.startsWith(_marker)) {
      setState(() {
        _cwd = clean.substring(_marker.length).trim();
        _busy = false;
      });
      return;
    }
    setState(() {
      _lines.add(line);
      if (_lines.length > 5000) _lines.removeRange(0, _lines.length - 5000);
    });
    _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  String get _prompt {
    final home = _home?.path;
    if (home == null) return r'$';
    final shown = _cwd == home
        ? '~'
        : p.isWithin(home, _cwd)
            ? '~/${p.relative(_cwd, from: home).replaceAll(r'\', '/')}'
            : _cwd;
    return '$shown \$';
  }

  void _run(String command) {
    final shell = _shell;
    if (shell == null) return;
    final cmd = command.trim();
    if (cmd.isEmpty) return;
    setState(() {
      _lines.add('$_prompt $cmd');
      _busy = true;
    });
    if (cmd.isNotEmpty && (_history.isEmpty || _history.last != cmd)) _history.add(cmd);
    _historyPos = _history.length;
    if (cmd == 'clear') {
      setState(() => _lines.clear());
    }
    // After each command, print the folder we're in so the prompt follows `cd`.
    shell.write('$cmd\nprintf "\\n$_marker%s\\n" "\$PWD"\n');
    _input.clear();
    _focus.requestFocus();
    _toBottom();
  }

  /// Ctrl+C: stop everything that runs in this terminal and start fresh.
  Future<void> _interrupt() async {
    _sub?.cancel();
    _shell?.stop();
    setState(() {
      _lines.add('${RunningProcess.errorMark}^C stopped');
      _busy = false;
      _shell = null;
    });
    await _start();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowUp && _history.isNotEmpty) {
      _historyPos = (_historyPos - 1).clamp(0, _history.length - 1);
      _input.text = _history[_historyPos];
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowDown && _history.isNotEmpty) {
      _historyPos = (_historyPos + 1).clamp(0, _history.length);
      _input.text = _historyPos == _history.length ? '' : _history[_historyPos];
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.keyC && HardwareKeyboard.instance.isControlPressed) {
      if (_input.selection.isCollapsed) {
        _interrupt();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: tokens.codeBackground,
      appBar: AppBar(
        backgroundColor: tokens.codeBackground,
        title: Text('terminal', style: monoStyle(context, size: 16, weight: FontWeight.w700)),
        actions: [
          if (_home != null)
            IconButton(
              tooltip: 'Sandbox files (save copies from here)',
              icon: const Icon(Icons.folder_open_outlined),
              onPressed: () => showSandboxFiles(context, _home!, title: 'Sandbox files'),
            ),
          if (_shell != null)
            IconButton(
              tooltip: 'Stop what is running (Ctrl+C)',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: _interrupt,
            ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: () => setState(_lines.clear),
          ),
          IconButton(
            tooltip: 'Runtimes and sandbox',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const RuntimesPage())),
          ),
        ],
      ),
      body: _problem != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_problem!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      await Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const RuntimesPage()));
                      Sandbox.instance.recheck();
                      _start();
                    },
                    child: const Text('Open Runtimes and sandbox'),
                  ),
                ]),
              ),
            )
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _focus.requestFocus,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                        itemCount: _lines.length,
                        itemBuilder: (context, i) {
                          final line = _lines[i];
                          final err = line.startsWith(RunningProcess.errorMark);
                          return SelectableText(
                            err ? line.substring(1) : line,
                            style: monoStyle(context,
                                size: 13, color: err ? color.error : color.onSurface),
                          );
                        },
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: color.outlineVariant))),
                    child: Row(
                      children: [
                        Text(_prompt, style: monoStyle(context, size: 13.5, color: tokens.success)),
                        const SizedBox(width: 8),
                        if (_shell == null && _home != null)
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () {
                                  Sandbox.instance.recheck();
                                  _start();
                                },
                                icon: const Icon(Icons.restart_alt_rounded),
                                label: const Text('Restart shell'),
                              ),
                            ),
                          )
                        else
                        Expanded(
                          child: Focus(
                            onKeyEvent: _onKey,
                            child: TextField(
                              controller: _input,
                              focusNode: _focus,
                              autofocus: true,
                              enabled: _shell != null,
                              autocorrect: false,
                              enableSuggestions: false,
                              style: monoStyle(context, size: 13.5),
                              decoration: InputDecoration.collapsed(
                                  hintText: _busy ? 'running… (Ctrl+C to stop)' : 'type a command'),
                              onSubmitted: _run,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
