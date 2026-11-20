import '../../helpers/helper_methods.dart';
import '../notes/domain/entities/block.dart';
import '../notes/domain/entities/language.dart';
import '../notes/domain/entities/note.dart';
import '../notes/domain/entities/note_group.dart';

/// Sample notes and folders created on first launch, so the app isn't
/// empty and every feature has an example. People can delete them anytime.
class DemoContent {
  DemoContent._();

  static ({List<NoteEntity> notes, List<NoteGroupEntity> groups}) build() {
    final now = DateTime.now();
    String id() => uuid.generate();
    DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));

    NoteEntity note(
      String title,
      List<BlockEntity> blocks, {
      List<String> tags = const [],
      bool pinned = false,
      int minutesAgo = 0,
    }) =>
        NoteEntity(
          id: id(),
          title: title,
          tags: tags,
          blocks: blocks,
          isPinned: pinned,
          lastModified: ago(minutesAgo),
        );

    final startHere = note(
      'Start here',
      [
        NoteBlockEntity(
          id: id(),
          text: 'Welcome to CodeNote. Every note is made of blocks: text, '
              'code, markdown and images. Everything stays on this device.',
        ),
        MarkdownBlockEntity(id: id(), text: '''
### Quick tips
- Tap **+** for a new note, then add blocks from the bar at the bottom.
- Drag the **⠿ grip** on a block to reorder it.
- **Long-press a note** and drop it on a folder to move it there.
- Swipe a note **right to archive**, **left to trash**. Every swipe has Undo.
- Tap a **#tag** on the home screen to filter.
- In a code block, tap the language name to pick from 50+ languages.

These notes are examples. Delete them whenever you like.'''),
      ],
      tags: const ['welcome'],
      pinned: true,
    );

    final rust = note(
      'Rust: handle a missing value',
      [
        NoteBlockEntity(
            id: id(),
            text: 'Option chaining keeps "maybe there is no value" code short.'),
        CodeBlockEntity(id: id(), language: Language.rust, text: '''
fn first_word_len(text: Option<&str>) -> usize {
    text.and_then(|t| t.split_whitespace().next())
        .map(|w| w.len())
        .unwrap_or(0)
}'''),
      ],
      tags: const ['rust'],
      minutesAgo: 5,
    );

    final git = note(
      'Git: undo things safely',
      [
        CodeBlockEntity(id: id(), language: Language.bash, text: '''
# Undo the last commit, keep the changes
git reset --soft HEAD~1

# Throw away changes in one file
git restore path/to/file

# Find a lost commit
git reflog'''),
      ],
      tags: const ['git', 'cheatsheet'],
      minutesAgo: 9,
    );

    final python = note(
      'Python: read a file safely',
      [
        CodeBlockEntity(id: id(), language: Language.python, text: '''
from pathlib import Path

def read_lines(path: str) -> list[str]:
    file = Path(path)
    if not file.exists():
        return []
    return file.read_text(encoding="utf-8").splitlines()'''),
      ],
      tags: const ['python'],
      minutesAgo: 14,
    );

    final flutter = note(
      'Flutter: debounce a search box',
      [
        NoteBlockEntity(
            id: id(), text: 'Wait until typing stops before searching.'),
        CodeBlockEntity(id: id(), language: Language.dart, text: '''
Timer? _debounce;

void onSearchChanged(String query) {
  _debounce?.cancel();
  _debounce = Timer(const Duration(milliseconds: 300), () {
    search(query);
  });
}'''),
      ],
      tags: const ['flutter', 'dart'],
      minutesAgo: 20,
    );

    final sql = note(
      'SQL: top 3 per group',
      [
        CodeBlockEntity(id: id(), language: Language.sql, text: '''
SELECT *
FROM (
  SELECT name, team, score,
         ROW_NUMBER() OVER (PARTITION BY team ORDER BY score DESC) AS rank
  FROM players
) ranked
WHERE rank <= 3;'''),
      ],
      tags: const ['sql', 'interview'],
      minutesAgo: 26,
    );

    final markdown = note(
      'Markdown cheat sheet',
      [
        MarkdownBlockEntity(id: id(), text: '''
# Heading
**bold**, *italic*, `inline code`

- a list item
- another one

> a quote

[a link](https://github.com/mahmoudyosrimahmoud13/code_note)'''),
      ],
      tags: const ['cheatsheet'],
      minutesAgo: 33,
    );

    final groups = [
      NoteGroupEntity(
        id: id(),
        name: 'snippets',
        noteIds: [python.id, flutter.id, sql.id],
        lastModified: now,
      ),
      NoteGroupEntity(
        id: id(),
        name: 'cheat-sheets',
        noteIds: [markdown.id],
        lastModified: now,
      ),
    ];

    return (
      notes: [startHere, rust, git, python, flutter, sql, markdown],
      groups: groups,
    );
  }
}
