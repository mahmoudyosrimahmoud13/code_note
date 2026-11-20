import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/themes.dart';
import 'rich_output_view.dart';
import 'run_manager.dart';
import 'runtimes.dart';
import 'runtimes_page.dart';
import 'sandbox.dart';
import 'sandbox_files_sheet.dart';
import 'terminal_page.dart';

/// Output of a code block's run, under the code: live output, Stop, the
/// sandbox Files, an input line for scripts that ask questions, and
/// "Save output" into the note.
class RunPanel extends StatefulWidget {
  const RunPanel({super.key, required this.session, this.onSaveOutput});

  final RunSession session;
  final void Function(RunSession session)? onSaveOutput;

  @override
  State<RunPanel> createState() => _RunPanelState();
}

class _RunPanelState extends State<RunPanel> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  Timer? _ticker;

  RunSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.addListener(_changed);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (s.running && mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(RunPanel old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.removeListener(_changed);
      widget.session.addListener(_changed);
    }
  }

  @override
  void dispose() {
    s.removeListener(_changed);
    _ticker?.cancel();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  String _elapsed() {
    final d = DateTime.now().difference(s.startedAt);
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }

  Future<void> _files() async {
    final dir = await Sandbox.instance.space(s.spaceKey);
    if (mounted) await showSandboxFiles(context, dir, title: 'Sandbox files');
  }

  Future<void> _terminal() async {
    final dir = await Sandbox.instance.space(s.spaceKey);
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => TerminalPage(folder: dir)));
  }

  /// Text lines grouped together, with plots and tables in between, in the
  /// order the program printed them.
  List<Widget> _segments(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final out = <Widget>[];
    final text = <String>[];
    void flush() {
      if (text.isEmpty) return;
      out.add(SelectableText.rich(TextSpan(children: [
        for (final line in text)
          TextSpan(
            text: '${RunningProcess.plain(line)}\n',
            style: monoStyle(context, size: 12.5, color: RunningProcess.isError(line) ? color.error : null),
          ),
      ])));
      text.clear();
    }

    for (final line in s.lines) {
      final rich = RichOutput.parse(line);
      if (rich == null) {
        text.add(line);
      } else {
        flush();
        out.add(RichOutputView(rich, key: ValueKey(rich.path)));
      }
    }
    flush();
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final (statusText, statusColor) = s.error != null
        ? ('not started', color.error)
        : s.running
            ? ('running · ${_elapsed()}', tokens.success)
            : s.exitCode == 0
                ? (s.inKernel ? 'done' : 'done · exit 0', tokens.success)
                : s.inKernel
                    ? (s.exitCode == 130 ? 'interrupted' : 'error', color.error)
                    : ('stopped · exit ${s.exitCode}', color.error);

    return Container(
      decoration: BoxDecoration(
        color: color.surfaceContainerLowest,
        border: Border(top: BorderSide(color: color.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Icon(s.running ? Icons.circle : Icons.circle_outlined, size: 9, color: statusColor),
                const SizedBox(width: 8),
                Text(s.inKernel ? 'In [${s.count ?? ' '}]' : '// output',
                    style: monoStyle(context, size: 12, color: s.inKernel ? color.primary : tokens.subtle)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(statusText,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(context, size: 12, color: statusColor)),
                ),
                const Spacer(),
                if (s.running)
                  TextButton.icon(
                    onPressed: s.stop,
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: Text(s.inKernel ? 'Interrupt' : 'Stop'),
                    style: TextButton.styleFrom(foregroundColor: color.error),
                  ),
                if (s.inKernel && s.noteId != null)
                  IconButton(
                    tooltip: 'Restart kernel (forget this note\'s Python variables)',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.restart_alt_rounded, size: 19),
                    onPressed: () => RunManager.instance.restartKernel(s.noteId!),
                  ),
                IconButton(
                  tooltip: 'Sandbox files (save copies from here)',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.folder_open_outlined, size: 19),
                  onPressed: _files,
                ),
                IconButton(
                  tooltip: 'Terminal in this sandbox',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.terminal_rounded, size: 19),
                  onPressed: _terminal,
                ),
                if (!s.running && s.lines.isNotEmpty && widget.onSaveOutput != null)
                  IconButton(
                    tooltip: 'Save output into the note',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.note_add_outlined, size: 19),
                    onPressed: () => widget.onSaveOutput!(s),
                  ),
                if (!s.running)
                  IconButton(
                    tooltip: 'Close output',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 19),
                    onPressed: () => RunManager.instance.clear(s.blockId),
                  ),
              ],
            ),
          ),
          if (s.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(children: [
                Expanded(child: Text(s.error!, style: TextStyle(color: color.error, fontSize: 13.5))),
                if (s.error!.contains('Settings'))
                  TextButton(
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const RuntimesPage())),
                    child: const Text('Open'),
                  ),
              ]),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: s.rich.isEmpty ? 260 : 640),
              child: s.lines.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Text(s.running ? 'waiting for output…' : 'no output',
                          style: monoStyle(context, size: 12.5, color: tokens.subtle)),
                    )
                  : SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _segments(context),
                      ),
                    ),
            ),
          if (s.running)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: TextField(
                controller: _input,
                style: monoStyle(context, size: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'type an answer for the script and press Enter',
                  hintStyle: monoStyle(context, size: 12.5, color: tokens.subtle),
                  prefixText: '> ',
                ),
                onSubmitted: (v) {
                  s.send('$v\n');
                  _input.clear();
                },
              ),
            ),
        ],
      ),
    );
  }
}
