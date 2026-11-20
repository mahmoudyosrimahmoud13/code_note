# Changelog

All notable changes to CodeNote Community Edition. Newest first.
Each release on GitHub uses the matching section below as its notes.

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
