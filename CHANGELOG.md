# Changelog

All notable changes to CodeNote Community Edition. Newest first.
Each release on GitHub uses the matching section below as its notes.

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
