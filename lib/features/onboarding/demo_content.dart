import '../../helpers/helper_methods.dart';
import '../notes/domain/entities/block.dart';
import '../notes/domain/entities/language.dart';
import '../notes/domain/entities/note.dart';
import '../notes/domain/entities/note_group.dart';
import 'runner_demos.dart';

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
- In a code block, tap the language name to pick from 58 languages.
- Notes with HTML, CSS or JS get a **▶** button that runs them, and Python or Bash blocks run with their own **▶**.
- Press **▶ Run folder** on a folder to start everything in it (see **youtube-downloader** and **fastapi-todo**).
- Press **Ctrl+K** on a computer for every action.
- Want these examples back later? **Settings → Add sample notes**.

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

    final webDemo = note(
      'Run it: a tiny web page',
      [
        NoteBlockEntity(
            id: id(),
            text: 'Press ▶ at the top to run this note. The HTML, CSS and JS '
                'blocks are joined into one page.'),
        CodeBlockEntity(id: id(), language: Language.html, text: r'''
<h1>Hello from CodeNote</h1>
<p>You clicked <b id="count">0</b> times.</p>
<button id="btn">Click me</button>'''),
        CodeBlockEntity(id: id(), language: Language.css, text: r'''
body { font-family: sans-serif; padding: 24px; }
h1 { color: #7b5cff; }
button { padding: 10px 18px; border-radius: 8px; border: 0;
         background: #7b5cff; color: white; font-size: 16px; }'''),
        CodeBlockEntity(id: id(), language: Language.javaScript, text: r'''
let clicks = 0;
document.getElementById('btn').addEventListener('click', () => {
  clicks += 1;
  document.getElementById('count').textContent = clicks;
});'''),
      ],
      tags: const ['html', 'javascript'],
      minutesAgo: 2,
    );

    final twoSum = note(
      'LeetCode 1: Two Sum',
      [
        MarkdownBlockEntity(id: id(), text: r'''
**Problem:** return the indexes of the two numbers that add up to `target`.

**Idea:** walk the list once and remember each number's index in a dictionary. For each number, check if `target - number` was already seen.'''),
        CodeBlockEntity(id: id(), language: Language.python, text: r'''
def two_sum(nums: list[int], target: int) -> list[int]:
    seen = {}
    for i, n in enumerate(nums):
        if target - n in seen:
            return [seen[target - n], i]
        seen[n] = i
    return []

print(two_sum([2, 7, 11, 15], 9))  # [0, 1]'''),
        MarkdownBlockEntity(id: id(), text: r'''
**Time:** O(n) · **Space:** O(n)'''),
      ],
      tags: const ['interview', 'python'],
      minutesAgo: 7,
    );

    final devLog = note(
      'Dev log',
      [
        MarkdownBlockEntity(id: id(), text: r'''
### Today
- [x] Fixed the login bug on Android
- [x] Wrote tests for the search
- [ ] Review the pull request from Sara

### Learned
`git bisect` finds the commit that broke something by testing half the history at a time.

### Tomorrow
Start the settings page.'''),
      ],
      tags: const ['log'],
      minutesAgo: 11,
    );

    final javascript = note(
      'JavaScript: fetch with a timeout',
      [
        CodeBlockEntity(id: id(), language: Language.javaScript, text: r'''
async function getJson(url, ms = 5000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  try {
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}'''),
      ],
      tags: const ['javascript'],
      minutesAgo: 16,
    );

    final typescript = note(
      'TypeScript: a result type',
      [
        NoteBlockEntity(
            id: id(),
            text: 'Make errors part of the type, so the caller has to handle them.'),
        CodeBlockEntity(id: id(), language: Language.typeScript, text: r'''
type Result<T> =
  | { ok: true; value: T }
  | { ok: false; error: string };

function parseAge(input: string): Result<number> {
  const age = Number(input);
  if (Number.isNaN(age) || age < 0) {
    return { ok: false, error: `"${input}" is not an age` };
  }
  return { ok: true, value: age };
}'''),
      ],
      tags: const ['typescript'],
      minutesAgo: 18,
    );

    final go = note(
      'Go: a small JSON API',
      [
        CodeBlockEntity(id: id(), language: Language.go, text: r'''
package main

import (
	"encoding/json"
	"net/http"
)

type Health struct {
	Status string `json:"status"`
}

func main() {
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(Health{Status: "ok"})
	})
	http.ListenAndServe(":8080", nil)
}'''),
      ],
      tags: const ['go'],
      minutesAgo: 22,
    );

    final cpp = note(
      'C++: count words',
      [
        CodeBlockEntity(id: id(), language: Language.cpp, text: r'''
#include <iostream>
#include <map>
#include <sstream>
#include <string>

int main() {
    std::string text = "the cat and the hat";
    std::map<std::string, int> counts;
    std::istringstream words(text);
    for (std::string w; words >> w;) counts[w]++;
    for (const auto& [word, n] : counts)
        std::cout << word << ": " << n << "\n";
}'''),
      ],
      tags: const ['cpp'],
      minutesAgo: 24,
    );

    final kotlin = note(
      'Kotlin: data classes',
      [
        CodeBlockEntity(id: id(), language: Language.kotlin, text: r'''
data class User(val name: String, val age: Int)

fun main() {
    val ali = User("Ali", 25)
    val older = ali.copy(age = 26)   // a new object, ali is unchanged
    println(older)                   // User(name=Ali, age=26)
    println("${ali.name} is ${ali.age}")
}'''),
      ],
      tags: const ['kotlin'],
      minutesAgo: 28,
    );

    final docker = note(
      'Docker: a small Python image',
      [
        CodeBlockEntity(id: id(), language: Language.docker, text: r'''
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]'''),
        CodeBlockEntity(id: id(), language: Language.bash, text: r'''
docker build -t my-api .
docker run -p 8000:8000 my-api'''),
      ],
      tags: const ['docker', 'devops'],
      minutesAgo: 35,
    );

    final actions = note(
      'GitHub Actions: test on every push',
      [
        CodeBlockEntity(id: id(), language: Language.yaml, text: r'''
name: tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - run: pip install -r requirements.txt
      - run: pytest'''),
      ],
      tags: const ['devops', 'ci'],
      minutesAgo: 40,
    );

    final linux = note(
      'Linux: who is using this port?',
      [
        CodeBlockEntity(id: id(), language: Language.bash, text: r'''
# Which program is listening on port 8000?
sudo lsof -i :8000

# Same with ss
ss -ltnp | grep :8000

# Stop it by its process id
kill <PID>'''),
      ],
      tags: const ['linux', 'cheatsheet'],
      minutesAgo: 45,
    );

    final regex = note(
      'Regex cheat sheet',
      [
        MarkdownBlockEntity(id: id(), text: r'''
| Pattern | Matches |
| --- | --- |
| `\d` | a digit |
| `\w` | a letter, digit or _ |
| `\s` | a space, tab or new line |
| `.` | any character |
| `^` and `$` | start and end of the line |
| `a*` `a+` `a?` | 0 or more, 1 or more, 0 or 1 |
| `[abc]` | a, b or c |
| `(cat\|dog)` | cat or dog |'''),
        CodeBlockEntity(id: id(), language: Language.python, text: r'''
import re
email = re.compile(r"^[\w.+-]+@[\w-]+\.[\w.]+$")
print(bool(email.match("me@example.com")))  # True'''),
      ],
      tags: const ['cheatsheet', 'regex'],
      minutesAgo: 50,
    );

    final json = note(
      'JSON: an API response',
      [
        CodeBlockEntity(id: id(), language: Language.json, text: r'''
{
  "id": 42,
  "name": "CodeNote",
  "tags": ["flutter", "notes"],
  "owner": { "login": "mahmoudyosrimahmoud13" },
  "stars": 128,
  "archived": false
}'''),
      ],
      tags: const ['json'],
      minutesAgo: 55,
    );

    final bigO = note(
      'Big-O cheat sheet',
      [
        MarkdownBlockEntity(id: id(), text: r'''
| Operation | List | Dict / Set |
| --- | --- | --- |
| Get by index | O(1) | |
| Find a value | O(n) | O(1) |
| Add at the end | O(1) | O(1) |
| Insert at the start | O(n) | |
| Sort | O(n log n) | |

Binary search: **O(log n)** on a sorted list.'''),
      ],
      tags: const ['interview', 'cheatsheet'],
      minutesAgo: 60,
    );

    final groups = [
      NoteGroupEntity(
        id: id(),
        name: 'snippets',
        noteIds: [python.id, flutter.id, javascript.id, typescript.id, go.id, cpp.id, kotlin.id],
        lastModified: now,
      ),
      NoteGroupEntity(
        id: id(),
        name: 'cheat-sheets',
        noteIds: [markdown.id, regex.id, bigO.id, linux.id],
        lastModified: now,
      ),
      NoteGroupEntity(
        id: id(),
        name: 'interview',
        noteIds: [twoSum.id, sql.id],
        lastModified: now,
      ),
      NoteGroupEntity(
        id: id(),
        name: 'devops',
        noteIds: [docker.id, actions.id],
        lastModified: now,
      ),
    ];

    final runnable = RunnerDemos.build();
    return (
      notes: [
        startHere, webDemo, rust, twoSum, git, devLog, python, javascript,
        typescript, flutter, go, cpp, sql, kotlin, markdown, docker,
        actions, linux, regex, json, bigO, ...runnable.notes,
      ],
      groups: [...groups, ...runnable.groups],
    );
  }
}
