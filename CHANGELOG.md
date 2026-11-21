# Changelog

All notable changes to CodeNote Community Edition. Newest first.
Each release on GitHub uses the matching section below as its notes.

## [1.12.0] - 2026-11-21

### New
- **Reminders look better and do more.** On Android the reminder alert uses CodeNote's violet, shows the whole message when you pull it down, and says when it was due. Tapping it opens the note (it used to just open the app), and **Snooze 10 min** brings it back later. On iPhone and Mac it shows the time and groups reminders together.
- **New reminder pop-up on Windows and Linux**, in the app's style, with the time, the message in its own box, **Snooze 10 min** and **Open note**.
- **Clearer messages at the bottom of the screen.** They all have the same rounded shape and spacing now, and confirmations and errors get an icon. Errors stay up a little longer so you can read them.

### Fixed
- **Scan text was rebuilt.** You can now take a photo with the camera, not only pick one from the gallery. The text is read right away (no separate Extract button), with a progress bar while it works. Before, a large "Choose Image" title didn't fit on phones, the add buttons were unlabeled icons under the keyboard, and the full-size photo used a lot of memory.
  - The result has a line count and a **Copy** button, and you can fix it before adding it.
  - Choose **Text** or **Code**. CodeNote guesses which one it is, and for code it guesses the language (you can change it).
  - **Retake** or pick **Other photo** at any time. If no text is found, it says how to take a better photo.

## [1.11.0] - 2026-11-21

### New
- **Link previews in text blocks.** Links you paste or type in a text block are highlighted as you write, and a card appears under the text with the page's picture, title, description and site. Tap the card to open the link, long-press it to copy the link.
- **Links on the home screen.** Note cards highlight links in their preview text and show a small card for the first link, so a note full of links is easy to spot.
- **Settings → Links.** Link previews are on by default. CodeNote opens each page once a week at most to make its card, and keeps the card on your device. Turn it off to never contact sites (links are still highlighted), or clear the saved cards.

## [1.10.0] - 2026-11-21

### New
- **Works with inPace.** In inPace (1.31.0 and newer), lessons with code and practical tasks get a **Practice in CodeNote** button. It opens the lesson in CodeNote as a note: the text becomes Markdown blocks and every code example a block you can run, on your computer or your phone. A practical task comes with its prompt and an empty block for your answer.
  - The note says which course and lesson it came from, and its ⋮ menu has **Back to inPace** and **Export for inPace** (an HTML report with your code, output and charts, to attach to the task as your work).
  - Opening the same lesson again opens your note. If the lesson changed in inPace, CodeNote asks whether to open your note or get the new version as a new note.
  - CodeNote registers `codenote://` links on Android, Windows, Linux (installed .deb) and macOS, which is also how inPace knows CodeNote is installed.
- **Markdown files open as runnable notes.** Any `.md` file (shared into CodeNote, opened from the file manager, or opened as a note in a workspace) becomes text blocks plus a code block for every ``` example.
- **Open page on the website** for `codenote://` links when CodeNote isn't installed: it can download the lesson as a `.md` file to open later.

## [1.9.2] - 2026-11-21

### Fixed
- Phones: the top bar had too many buttons, so the title and note count were cut off. It now keeps search, open and your profile, with Commands and New group in a ⋮ menu, and the title fits.

## [1.9.1] - 2026-11-21

### Fixed
- Phones: the notes list could stop scrolling before the last notes. It now always scrolls to the end.
- Phones: the top bar (title, search, commands, open) stays at the top while the notes scroll under it, like other Android apps.
- Data viewer: on wide screens the table now starts at the left, and numbers show without extra zeros (17.1, not 17.100).

## [1.9.0] - 2026-11-20

Data science in your pocket.

### New
- **Python on phones.** Python blocks now run on Android (and iPhone) with Pyodide, Python built for WebAssembly, inside CodeNote's own sandbox. It's the same kernel as on computers, so notes, Run note, Run folder, the run order and workspaces all work the same: blocks share variables, tables and plots show under the code, Interrupt and Restart work.
  - **Download what you need, like the other runtimes:** Settings > Runtimes and sandbox has "Download Python" (about 12 MB) and a data science set (numpy, pandas, matplotlib, seaborn, scipy, scikit-learn, openpyxl), plus any other Pyodide or pure-Python package. Everything works offline afterwards.
  - If a block imports something you haven't downloaded, a card under it says what's missing with a **Download** button.
  - Python runs in a background worker, so heavy code never freezes the app.
- **Workspaces (open a folder like an IDE).** On a computer open a folder, on a phone pick files. They're copied into a sandbox and shown as a file tree. Open a file **as a file** (edit, Save, Run) or **as a note**: `.ipynb` becomes cells, `.py` splits into blocks at `# %%` lines. Notes remember their file and save back into it. **Save back** copies changed files into the original folder after showing you the list. Every CodeNote folder now has a **Files** button that opens it as a workspace.
- **Data viewer.** Open a CSV, TSV, JSON or JSON Lines file and get a table you can search and sort, a summary of every column (numbers or text, missing values, smallest, largest, average, median, most common values) and a chart per column. Big files load in the background and scroll smoothly. **Analyze in a notebook** writes a pandas notebook for the file: first rows, types, summary, missing values, histograms and a correlation chart. Excel and Parquet files open straight in that notebook.
- **Snippets.** Python blocks get a **Snippet** button: load, look, clean, shape, chart, model (scikit-learn) and save, ready to run.
- **Export** a note as a **Jupyter notebook** (`.ipynb`) or as an **HTML report** with its text, code, tables and plots.
- A folder button on the home screen opens a folder, a data file or a notebook. Data files shared into CodeNote open in the data viewer.
- **Open Jupyter notebooks** (`.ipynb`) as notes: Markdown cells become Markdown blocks, code cells become code blocks in the notebook's language, and saved outputs (text, tables, plots, errors) come along. Ctrl+K → "Open a Jupyter notebook", share or "Open with" on Android, Linux and Windows.
- **Jupyter keyboard shortcuts** in code blocks: Shift+Enter runs and moves to the next block (adds one at the end), Ctrl+Enter runs and stays, Alt+Enter runs and adds a block below. Esc selects the block (command mode), where A / B add a block above / below, D D deletes, M turns it into Markdown, ↑ ↓ (or K J) move between blocks, I I stops the code and 0 0 restarts the Python kernel. The full list is in the note's ⋮ menu under Keyboard shortcuts.
- **Expose sandbox** (Settings > Runtimes and sandbox, off by default): lets code you trust read and change your own files, not only its sandbox folder. Your real home folder is in `$CODENOTE_HOME`. Asks before turning on, and the sandbox card says when it's on. Linux and Windows; Android and macOS keep CodeNote in its own space. Also new: **Open the sandbox folder** in your file manager.
- **Double-click a .codenote file** to open it in CodeNote: on Linux (installed .deb), Windows and Android. If CodeNote is already open, the file goes to that window.
- **Share menu:** "CodeNote file (.codenote)" is now the first choice in a note's share sheet.

### Fixed
- `%pip install --quiet …` on computers no longer looks stuck: a ticking line shows it's still downloading, and the end says "✓ pip finished" or why it stopped. Interrupt also stops the download.
- Shell commands in Python blocks (`!cmd`, `%pip`) can't read the kernel's own input anymore.

## [1.8.0] - 2026-11-20

### New
- **Python works like Jupyter.**
  - **Shared variables:** the Python blocks of a note share one kernel, so `df` made in one block is there in the next.
  - **Like Jupyter cells:** each run shows its **In [n]** counter, the last line's value is shown automatically, and `display(x)` works anywhere.
  - **Interrupt** stops a block and keeps the variables. **Restart kernel** forgets them.
  - **Jupyter's shortcuts:** `!ls` and `%pip install …` lines work as in Jupyter.
  - **Servers aren't blocked:** ★ primary and keep-running blocks still get their own process, so a server never blocks the notebook.
- **Rich output, for any library that supports Jupyter's display:**
  - **Plots:** matplotlib and seaborn plots show as images, even without `plt.show()`.
  - **Tables:** pandas (and polars) tables show as real tables, with their size.
  - **Images and markdown:** from Pillow, torchvision and more.
  - **Interactive HTML** (plotly, folium, pandas Styler) gets an **Open** button.
  - **Progress bars** (tqdm, pip) redraw in place.
  - **Saving:** "Save output into the note" keeps plots as image blocks and tables as Markdown tables.
  - **Started from anywhere:** this also works for Python started from Bash or the terminal.
- **New notebooks folder:**
  - **Data science** (numpy, pandas, seaborn)
  - a **Pandas cookbook** (CSV, filter, groupby, pivot, merge, resample, text, missing values, styling, plots)
  - **PyTorch** (training a tiny model with tqdm and plotting it)

### Fixed
- **Linux sandbox:** bubblewrap failed with "Can't mkdir /run/media" on systems without that folder (Zorin, Ubuntu), so the terminal and every run stopped at once.
  - **Hiding:** the sandbox now hides only folders that exist, plus your real home folder wherever it is.
  - **Self-test:** CodeNote tests bubblewrap before using it, and Settings explains if it can't be used.
- **Terminal:** it now notices when the shell closes and offers **Restart shell**, instead of saying "running…" forever.

## [1.7.0] - 2026-11-20

### New
- **Run order for folders.** ▶ Run folder now runs notes one after another, in an order you set with the new **Run order** button.
  - Each note finishes before the next starts, unless you set it to **keep running**.
  - The **★ primary** note always runs last and keeps running (a server, usually). Then the folder's web pages open.
  - A "step 2 of 4" line shows progress.
- **The same sequence inside a note.** A new **▶ Run note** button in the note's top bar runs its blocks top to bottom.
  - Mark a block **★ primary** (runs last, keeps running), **keep running** (the next block doesn't wait) or **skip**.
  - Cards preview the primary block's code, and a **★ primary** chip under the title jumps to it.
- **JavaScript and TypeScript with Node.js.** Download Node.js (newest LTS, from nodejs.org) in **Settings → Runtimes and sandbox**, or use the one you have.
  - JavaScript and TypeScript blocks in notes without HTML get a ▶. In a web page note they stay part of the page.
  - `node` and `npm` work in the terminal.
  - Global npm packages can be installed, updated and removed in Settings.
- **Dart.** Download the official Dart SDK (stable) in Settings, or use the one you have. Dart blocks get a ▶, and `dart` works in the terminal.
- **.codenote files for sharing.** Share a note (⋯ menu) or a whole folder with its run order (folder page) as one `.codenote` file, with images and saved app data.
  - Open one with **Ctrl+K → Open a .codenote file**, from Backup, or with "open with / share" on Android. It merges in and never deletes anything.
- **Download progress for packages:** a bar for each file pip downloads, pinned at the top of the Runtimes page.
- **A spinning ring on ▶ while code runs:** on blocks, on Run note and on Run folder.
- **New samples:**
  - a **pipeline** folder (Python makes data → Node.js adds it up → Dart writes a report → a Node.js primary server feeds a chart page)
  - Node.js, TypeScript and Dart samples in **run-code**

### Improved
- **Notes use the full window width on desktop,** with wider side margins on big screens.
- The web page button in a note is now an "open in browser" icon, since ▶ runs the note.

## [1.6.0] - 2026-11-20

### New
- **Run Python and Bash in your notes.** Python, Bash and PowerShell (Windows) code blocks get a small **▶**. Output shows under the code, with Stop, an input line for scripts that ask questions, and "Save output into the note".
- **Everything runs in a sandbox.** Each folder of notes has its own sandbox folder, shared by the notes in it, so a backend in one note and a web page in another work together.
  - **Android:** Android's own app sandbox.
  - **macOS:** Apple's App Sandbox.
  - **Linux:** bubblewrap. Scripts can't see your home folder.
  - **Windows** (and Linux without bubblewrap): only a private folder, so running code is off until you allow it in Settings.
- **Files stay in the sandbox** until you choose **Save a copy** from the Files button.
- **▶ Run folder** starts every note in a folder, then opens its web pages. Mark a block **★ main** (the only one that runs with the folder) or **skip**.
- **Runs keep going** when you leave the note, with a "● running" badge on the note card and Stop all in the command palette and Settings.
- **Terminal:** a real shell inside the sandbox, from the sidebar, `Ctrl+K`, or the terminal button under any output.
- **Settings → Runtimes and sandbox:**
  - Download Python (python-build-standalone) or BusyBox Bash for Windows from their official sources.
  - Install, update and remove Python packages. They live in CodeNote's own environment and never change your system.
  - See what's running, and clear sandbox files.
- **Mini apps:** web page notes can now save data. `localStorage` just works, and is kept per note and in backups.
  - `codenote.storage` saves values.
  - `codenote.api(8000, '/path')` calls a server started in the same folder, without CORS problems.
  - `codenote.file('name')` shows a file from the folder's sandbox.
- **New sample notes:**
  - **youtube-downloader** (yt-dlp with video or audio, quality, formats, subtitles, thumbnails, SponsorBlock, playlists, speed limit, live progress)
  - **fastapi-todo** (a FastAPI backend and its frontend)
  - **Snake**, a mini app game that saves your best score
  - small Python and Bash scripts
- Onboarding explains the sandbox.

### Improved
- **Markdown on note cards and folder previews looks like Markdown:** headings, bold, code, lists and checkboxes instead of raw `#` and `**`.

## [1.5.2] - 2026-11-20

### Fixed
- **Line numbers in code blocks no longer break apart.** From line 10 on, numbers like 42 were split onto two rows ("4" then "2"), so the number column ran far below the code. It was worse with bigger text. The column now grows to fit the longest number, and follows your text size.

### New
- **14 more sample notes:** a web page you can run with ▶, LeetCode Two Sum, a dev log, JavaScript, TypeScript, Go, C++, Kotlin, Docker, GitHub Actions, Linux ports, regex and Big-O cheat sheets, and a JSON example. New `interview` and `devops` folders.
- **Settings → Add sample notes** adds them any time. Notes you already have are kept and never copied twice.

## [1.5.1] - 2026-11-20

### Fixed
- **CodeNote now starts on every Linux setup.** On systems without a Documents folder helper (some minimal or non-GNOME desktops) it stopped at the startup screen. Your notes stay in the same place.
- **Markdown blocks use the full width** of the note again, instead of being squeezed into the middle.
- **Dark logos are visible in dark mode:** Bash, ARM, Lua, Gradle and Erlang now sit on a small light tile.
- **Ask your notes lists only relevant sources** and leaves out notes that barely match.
- The startup error message now explains the real cause instead of always blaming a second window.

### Docs
- New README posters and screenshots, taken from the real 1.5.0 app.

## [1.5.0] - 2026-11-20

### New
- **Ask your notes.** Ask a question in plain words and the AI answers from your own notes, showing which notes it used. Save the answer as a note. Only the few notes that match are sent.
- **Run HTML, CSS and JS.** Notes with web code get a ▶ button that shows the result live (inside the app on phones, in your browser on desktop).
- **Real reminder notifications.** Reminders now pop up as system notifications on Android, iOS and macOS, even when CodeNote is closed. On Windows and Linux they appear while the app is open.
- **Templates.** Start a note from a bug report, dev log, LeetCode, meeting, API endpoint or snippet template, or save any note as your own template.
- **GitHub Gist import and export.** Paste a gist link to turn it into a note, or upload a note as a secret gist and get the link copied.
- **Language logos are back.** Code blocks, the language list and note cards show each language's logo again, now for 55 languages.

### Fixed
- **Opening CodeNote twice on Windows or Linux** now brings the open window to the front instead of starting a broken second copy.
- **Rounded app icon** on the Windows and Linux taskbar (same logo, no more sharp square corners). macOS uses the standard rounded shape too.
- If CodeNote ever can't open your notes at startup, it now says so clearly instead of showing an empty screen.

## [1.4.0] - 2026-11-20

### New
- **Backup and restore.** Save every note, folder and image to one `.codenote` file, and restore it on any device. Restoring merges: nothing you already have is deleted.
- **Automatic daily backup** (desktop). Pick a folder (Dropbox, Google Drive, Syncthing, a Git repo) and CodeNote saves a backup there once a day, keeping the last 10.
- **Share code as an image.** Turn any code block into a clean picture for X, LinkedIn or Discord, with a choice of backgrounds.
- **Command palette.** Press `Ctrl+K` (`Cmd+K` on Mac) to search notes and run any action from the keyboard.
- **Update check.** CodeNote tells you when a new version is out, with what changed and a download button. It can be turned off in Settings.
- **Finds local AI models automatically.** AI settings lists the models installed in Ollama and LM Studio on your computer. Tap one to use it, no key needed.
- Release pages now include install steps for every platform and a checksums file.

## [1.3.0] - 2026-11-20

### New
- **AI assistant on code blocks.** Tap ✨ to explain code, find bugs or get improvement ideas, then save the answer into the note. Works with Claude, OpenAI-compatible APIs, or Ollama for fully offline use. Off until you set it up, and only the code you ask about is sent.
- **Desktop sidebar** with note counts, folders (drop notes on them) and tags.
- **Keyboard shortcuts:** `Ctrl+N` new note, `Ctrl+F` search, `Esc` close search.
- The layout follows the window size: sidebar, slim rail, or phone layout.

## [1.2.1] - 2026-11-20

### New
- **Folder previews:** folder cards show image thumbnails, code and text of the notes inside.
- **58 code languages** (was 21), with a searchable picker. Shared files get the right language automatically.
- **Language labels** on every note card.
- **Drag to reorder** blocks with the grip on each block.
- **Welcome notes and folders** on first launch.

### Fixed
- Notes created inside a folder weren't added to it.
- Undo messages stayed on screen until tapped.

## [1.2.0] - 2026-11-20

### New
- New look with a terminal personality, a real code font (JetBrains Mono), and new onboarding.
- Builds for Android, Windows, Linux (`.deb` and `.tar.gz`) and macOS.

### Fixed
- Faster: each note is saved on its own, and the app no longer slows down over time.
- Your last keystrokes are saved when you leave a note.
- "Delete forever" now really deletes. Trash empties itself after 30 days.
- Shared items are saved right away; shared photos are no longer ignored.

### Important
- **Coming from 1.1.0 on Android:** 1.1.0 was signed with a key that no longer exists, so Android can't update it in place. Copy out any notes you want to keep, uninstall 1.1.0, then install this version. Every update after this one installs normally.
