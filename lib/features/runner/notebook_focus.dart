import 'package:flutter/material.dart';

/// Moves the keyboard between code blocks, like cells in Jupyter.
///
/// Each code block registers how to focus itself. Asking for a block that
/// isn't on screen yet (just added) waits until it's built.
class NotebookFocus {
  NotebookFocus._();

  static final _focusers = <String, void Function(bool edit)>{};
  static final _pending = <String, bool>{};

  static void register(String id, void Function(bool edit) focus) {
    _focusers[id] = focus;
    final edit = _pending.remove(id);
    if (edit != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusers[id]?.call(edit));
    }
  }

  static void unregister(String id, void Function(bool edit) focus) {
    if (identical(_focusers[id], focus)) _focusers.remove(id);
  }

  /// Focuses block [id]: [edit] puts the cursor in the code, otherwise the
  /// block is selected (command mode) so single-key shortcuts work.
  static void focus(String id, {bool edit = true}) {
    final f = _focusers[id];
    if (f != null) {
      f(edit);
    } else {
      _pending[id] = edit;
    }
  }
}

/// What a code block can ask its note to do (given through NoteScope).
class NotebookActions {
  const NotebookActions({
    required this.next,
    required this.previous,
    required this.insert,
    required this.toMarkdown,
    required this.delete,
  });

  /// Selects the next code block, or adds one when this is the last.
  final void Function(String id) next;

  /// Selects the code block before this one.
  final void Function(String id) previous;

  /// Adds an empty code block above or below and puts the cursor in it.
  final void Function(String id, {required bool above}) insert;

  /// Turns the code block into a Markdown block with the same text.
  final void Function(String id) toMarkdown;

  /// Deletes the block (with Undo) and selects the next one.
  final void Function(String id) delete;
}

/// The shortcuts, for the help sheet.
const notebookShortcuts = <(String, String)>[
  ('Shift + Enter', 'Run, then go to the next block (adds one at the end)'),
  ('Ctrl + Enter', 'Run and stay'),
  ('Alt + Enter', 'Run, then add a block below'),
  ('Esc', 'Leave the code: select the block (command mode)'),
  ('Enter', 'Command mode: back into the code'),
  ('A / B', 'Command mode: add a block above / below'),
  ('D, D', 'Command mode: delete the block (Undo stays)'),
  ('M', 'Command mode: turn into Markdown'),
  ('↑ / K, ↓ / J', 'Command mode: previous / next block'),
  ('I, I', 'Command mode: stop the running code'),
  ('0, 0', 'Command mode: restart the Python kernel'),
];

/// A sheet listing the Jupyter-style shortcuts.
void showNotebookShortcuts(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        children: [
          Text('Keyboard shortcuts', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Like Jupyter. They work in code blocks with a keyboard. On a Mac use Cmd instead of Ctrl.',
            style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          for (final (keys, what) in notebookShortcuts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 130,
                  child: Text(keys, style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                ),
                Expanded(child: Text(what)),
              ]),
            ),
        ],
      ),
    ),
  );
}
