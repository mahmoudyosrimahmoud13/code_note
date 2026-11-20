import 'dart:io';

import 'package:flutter/material.dart';

import '../../constants/themes.dart';
import '../../widgets/brand.dart';
import 'run_manager.dart';
import 'runtimes.dart';
import 'sandbox.dart';
import 'terminal_page.dart';

/// Settings > Runtimes and sandbox.
class RuntimesPage extends StatefulWidget {
  const RuntimesPage({super.key});

  @override
  State<RuntimesPage> createState() => _RuntimesPageState();
}

class _RuntimesPageState extends State<RuntimesPage> {
  final rt = Runtimes.instance;
  final sb = Sandbox.instance;

  SandboxLevel? _level;
  bool _allowed = false;
  String? _pyVersion;
  String? _pyPath;
  bool _pyDownloaded = false;
  bool _hasEnv = false;
  (String, List<String>)? _shell;
  bool _busyboxDownloaded = false;
  List<PythonPackage> _packages = const [];
  bool _checkedUpdates = false;
  String? _nodeVersion;
  bool _nodeDownloaded = false;
  List<PythonPackage> _npmPackages = const [];
  bool _checkedNpmUpdates = false;
  String? _dartVersion;
  bool _dartDownloaded = false;
  final _npmInput = TextEditingController();

  String? _task; // what's happening now
  double? _progress;
  final _log = <String>[];
  final _pkgInput = TextEditingController();

  @override
  void initState() {
    super.initState();
    RunManager.instance.addListener(_refreshRuns);
    _refresh();
  }

  @override
  void dispose() {
    RunManager.instance.removeListener(_refreshRuns);
    _pkgInput.dispose();
    _npmInput.dispose();
    super.dispose();
  }

  void _refreshRuns() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh({bool packages = true}) async {
    sb.recheck();
    final level = await sb.level();
    final allowed = await sb.folderSandboxAllowed();
    final py = await rt.pythonForRuns();
    final version = await rt.pythonVersion();
    final downloaded = await rt.isPythonDownloaded();
    final hasEnv = await rt.hasEnvironment();
    final shell = await rt.shell();
    final bb = await rt.isBusyboxDownloaded();
    final nodeV = await rt.nodeVersion();
    final nodeD = await rt.isNodeDownloaded();
    final dartV = await rt.dartVersion();
    final dartD = await rt.isDartDownloaded();
    if (!mounted) return;
    setState(() {
      _nodeVersion = nodeV;
      _nodeDownloaded = nodeD;
      _dartVersion = dartV;
      _dartDownloaded = dartD;
      _level = level;
      _allowed = allowed;
      _pyPath = py;
      _pyVersion = version;
      _pyDownloaded = downloaded;
      _hasEnv = hasEnv;
      _shell = shell;
      _busyboxDownloaded = bb;
    });
    if (packages && hasEnv) await _loadPackages();
    if (packages && nodeV != null) await _loadNpm();
  }

  Future<void> _loadNpm({bool updates = false}) async {
    await _doing(updates ? 'Checking npm for updates…' : 'Reading npm packages…', () async {
      final list = await rt.npmPackages(checkUpdates: updates);
      if (mounted) setState(() {
        _npmPackages = list;
        _checkedNpmUpdates = updates;
      });
    });
  }

  Future<void> _loadPackages({bool updates = false}) async {
    await _doing(updates ? 'Checking for updates…' : 'Reading packages…', () async {
      final list = await rt.packages(checkUpdates: updates);
      if (mounted) setState(() {
        _packages = list;
        _checkedUpdates = updates;
      });
    });
  }

  Future<void> _doing(String label, Future<void> Function() work) async {
    if (_task != null) return;
    setState(() {
      _task = label;
      _progress = null;
    });
    try {
      await work();
    } on RuntimeException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() {
        _task = null;
        _progress = null;
      });
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), persist: false));
  }

  void _progressCb(double f, String status) {
    if (mounted) setState(() {
      _progress = f;
      _task = status;
    });
  }

  /// Runs pip (or npm) and shows its output in the log. pip's download
  /// progress drives the bar at the top; other lines say what's happening.
  Future<void> _pip(String label, List<String> args, {bool npm = false}) async {
    await _doing(label, () async {
      var cmd = args;
      if (!npm && args.first == 'install' && await rt.pipReportsProgress()) {
        cmd = [...args, '--progress-bar=raw'];
      }
      setState(() => _log
        ..clear()
        ..add('\$ ${npm ? 'npm' : 'pip'} ${args.join(' ')}'));
      final proc = npm ? await rt.npm(cmd) : await rt.pip(cmd);
      await for (final line in proc.lines) {
        if (!mounted) break;
        final clean = line.startsWith(RunningProcess.errorMark) ? line.substring(1) : line;
        final fraction = npm ? null : Runtimes.pipProgress(clean);
        if (fraction != null) {
          setState(() => _progress = fraction);
          continue;
        }
        final t = clean.trim();
        setState(() {
          _log.add(line);
          if (t.startsWith('Downloading ') || t.startsWith('Collecting ')) {
            _task = t.length > 90 ? '${t.substring(0, 90)}…' : t;
            _progress = t.startsWith('Downloading ') ? 0 : null;
          } else if (t.startsWith('Installing collected packages')) {
            _task = 'Installing…';
            _progress = null;
          }
        });
      }
      final code = await proc.exitCode;
      if (mounted) setState(() => _log.add(code == 0 ? '✓ done' : '${RunningProcess.errorMark}✗ exited with $code'));
    });
    await _refresh();
  }

  Future<void> _install() async {
    final names = _pkgInput.text
        .split(RegExp(r'[\s,]+'))
        .where((e) => e.isNotEmpty)
        .map(Runtimes.cleanPackageName)
        .toList();
    if (names.isEmpty || names.contains(null)) {
      _snack('Type package names like: yt-dlp requests');
      return;
    }
    _pkgInput.clear();
    await _pip('Installing ${names.join(', ')}…', ['install', '--upgrade', ...names.cast<String>()]);
  }

  Future<void> _updateAll() async {
    final outdated = _packages.where((p) => p.outdated).map((p) => p.name).toList();
    if (outdated.isEmpty) {
      _snack('Everything is up to date.');
      return;
    }
    await _pip('Updating ${outdated.length} packages…', ['install', '--upgrade', ...outdated]);
  }

  Future<void> _npmInstall() async {
    final names = _npmInput.text
        .split(RegExp(r'[\s,]+'))
        .where((e) => e.isNotEmpty)
        .map(Runtimes.cleanNpmName)
        .toList();
    if (names.isEmpty || names.contains(null)) {
      _snack('Type package names like: typescript prettier');
      return;
    }
    _npmInput.clear();
    await _pip('Installing ${names.join(', ')}…', ['install', '-g', ...names.cast<String>()], npm: true);
  }

  Widget _runtimeCard({
    required String logo,
    required String title,
    required String note,
    required bool canDownload,
    required bool downloaded,
    required String downloadLabel,
    required Future<void> Function() download,
    required Future<void> Function() remove,
    Widget? extra,
  }) {
    final tokens = context.tokens;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Image.asset(logo, width: 26, height: 26),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          ]),
          const SizedBox(height: 8),
          Text(note, style: TextStyle(color: tokens.subtle, fontSize: 13.5)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (canDownload)
              FilledButton.icon(
                onPressed: _task != null ? null : () => _doing(downloadLabel, download),
                icon: const Icon(Icons.download_rounded),
                label: Text(downloaded ? 'Download again (newest)' : downloadLabel),
              ),
            if (downloaded)
              TextButton.icon(
                onPressed: _task != null
                    ? null
                    : () async {
                        if (!await _confirm('Remove it?', 'The downloaded copy is removed from the sandbox. Your notes stay.', 'Remove')) {
                          return;
                        }
                        await _doing('Removing…', remove);
                      },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Remove'),
              ),
          ]),
          if (extra != null) ...[const SizedBox(height: 12), extra],
        ]),
      ),
    );
  }

  Widget _nodeCard() {
    return _runtimeCard(
      logo: 'assets/languages/javaScript.png',
      title: _nodeVersion == null ? 'Node.js: not set up' : 'Node.js $_nodeVersion',
      note: Platform.isMacOS
          ? 'Uses the Node.js installed on your Mac (for example from nodejs.org or Homebrew).'
          : 'Runs JavaScript and TypeScript blocks in notes without HTML, and node / npm in the terminal. '
              'Downloaded from nodejs.org (newest LTS) into the sandbox.',
      canDownload: Runtimes.canDownloadNode,
      downloaded: _nodeDownloaded,
      downloadLabel: 'Download Node.js',
      download: () async {
        await rt.downloadNode(onProgress: _progressCb);
        await _refresh();
      },
      remove: () async {
        await rt.removeNode();
        setState(() => _npmPackages = const []);
        await _refresh();
      },
      extra: _nodeVersion == null ? null : _npmSection(),
    );
  }

  Widget _npmSection() {
    final tokens = context.tokens;
    final outdated = _npmPackages.where((p) => p.outdated).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _npmInput,
            style: monoStyle(context, size: 14),
            decoration: const InputDecoration(hintText: 'npm install -g …  e.g. typescript prettier', isDense: true),
            onSubmitted: (_) => _npmInstall(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: _task != null ? null : _npmInstall, child: const Text('Install')),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Text('${_npmPackages.length} global packages', style: TextStyle(color: tokens.subtle)),
        if (_checkedNpmUpdates) ...[
          const SizedBox(width: 8),
          Text(outdated == 0 ? '· all up to date' : '· $outdated can update',
              style: TextStyle(color: outdated == 0 ? tokens.success : tokens.pin)),
        ],
        const Spacer(),
        TextButton(onPressed: _task != null ? null : () => _loadNpm(updates: true), child: const Text('Check for updates')),
        if (outdated > 0)
          FilledButton.tonal(
            onPressed: _task != null
                ? null
                : () => _pip('Updating npm packages…',
                    ['install', '-g', for (final p in _npmPackages.where((p) => p.outdated)) '${p.name}@latest'],
                    npm: true),
            child: const Text('Update all'),
          ),
      ]),
      for (final pkg in _npmPackages)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(pkg.name, style: monoStyle(context, size: 13.5)),
          subtitle: Text(pkg.outdated ? '${pkg.version} → ${pkg.latest}' : pkg.version,
              style: monoStyle(context, size: 12, color: pkg.outdated ? tokens.pin : tokens.subtle)),
          trailing: IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _task != null ? null : () => _pip('Removing ${pkg.name}…', ['uninstall', '-g', pkg.name], npm: true),
          ),
        ),
    ]);
  }

  Widget _dartCard() {
    return _runtimeCard(
      logo: 'assets/languages/dart.png',
      title: _dartVersion == null ? 'Dart: not set up' : 'Dart $_dartVersion',
      note: Platform.isMacOS
          ? 'Uses the Dart SDK installed on your Mac (for example from Homebrew or Flutter).'
          : 'Runs Dart blocks, and dart in the terminal. The stable SDK from Google\'s official Dart archive '
              '(about 200 MB once unpacked), kept in the sandbox. Analytics are turned off.',
      canDownload: Runtimes.canDownloadDart,
      downloaded: _dartDownloaded,
      downloadLabel: 'Download Dart',
      download: () async {
        await rt.downloadDart(onProgress: _progressCb);
        await _refresh(packages: false);
      },
      remove: () async {
        await rt.removeDart();
        await _refresh(packages: false);
      },
    );
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
        ],
      ),
    );
    return ok == true;
  }

  // ---------- UI ----------

  Widget _section(String label, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(top: 26),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CommentLabel(label),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _sandboxCard() {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final (icon, title, body) = switch (_level) {
      SandboxLevel.system => (
          Icons.verified_user_outlined,
          'Fully sandboxed',
          Platform.isAndroid
              ? "Android keeps CodeNote in its own sandbox. Scripts can only use CodeNote's private storage, never your photos or other apps."
              : "macOS keeps CodeNote in Apple's App Sandbox. Scripts can only use CodeNote's own folder, never your documents."
        ),
      SandboxLevel.bubblewrap => (
          Icons.verified_user_outlined,
          'Fully sandboxed (bubblewrap)',
          "Scripts see the system read-only and only their own sandbox folder. Your home folder, USB drives and other files are hidden from them. Internet works, so downloads and pip work."
        ),
      SandboxLevel.folderOnly => (
          Icons.shield_outlined,
          'Folder sandbox only',
          Platform.isLinux
              ? "Install bubblewrap for a full sandbox: sudo apt install bubblewrap, then tap Check again. Without it, scripts run in their own folder with their own home and temp folders, but a script could still reach your other files if it tried."
              : "Windows has no simple sandbox CodeNote can use. Scripts run in their own folder with their own home and temp folders, but a script could still reach your other files if it tried. Only run code you trust."
        ),
      _ => (Icons.block_rounded, 'Not available', "This device can't run code."),
    };
    final good = _level == SandboxLevel.system || _level == SandboxLevel.bubblewrap;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: good ? tokens.success : tokens.pin),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          ]),
          const SizedBox(height: 8),
          Text(body),
          const SizedBox(height: 10),
          Text(
            'Every folder of notes has its own sandbox folder. Notes in the same folder share it, so a backend '
            'and a web page can work together. Files your scripts make stay there until you choose "Save a copy".',
            style: TextStyle(color: tokens.subtle, fontSize: 13.5),
          ),
          if (_level == SandboxLevel.folderOnly) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow running code with the folder sandbox'),
              subtitle: const Text('Off by default. Turn on only if you run code you trust.'),
              value: _allowed,
              onChanged: (v) async {
                if (v &&
                    !await _confirm(
                        'Allow running code?',
                        'Scripts will run in their own folder, but on this computer CodeNote can\'t fully stop a script from reaching your other files. Only run code you trust.',
                        'Allow')) {
                  return;
                }
                await sb.setFolderSandboxAllowed(v);
                await _refresh(packages: false);
              },
            ),
            if (Platform.isLinux)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _refresh(packages: false),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Check again'),
                ),
              ),
          ],
          if (_level == SandboxLevel.unavailable)
            Text('iPhone and iPad don\'t allow apps to run code.', style: TextStyle(color: color.error)),
        ]),
      ),
    );
  }

  Widget _pythonCard() {
    final tokens = context.tokens;
    if (!Runtimes.pythonSupported) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.info_outline_rounded),
          title: Text('Python isn\'t available on this device yet'),
          subtitle: Text('Bash works. Python on phones is planned for a later version.'),
        ),
      );
    }
    final source = _pyDownloaded
        ? "CodeNote's own Python (in the sandbox)"
        : _pyPath != null
            ? 'Your system Python, with CodeNote\'s own packages'
            : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Image.asset('assets/languages/python.png', width: 26, height: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_pyVersion == null ? 'Python: not set up' : 'Python $_pyVersion',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          ]),
          if (source != null) ...[
            const SizedBox(height: 4),
            Text(source, style: TextStyle(color: tokens.subtle)),
          ],
          const SizedBox(height: 8),
          Text(
            Platform.isMacOS
                ? "Uses your Mac's Python. If it's missing, install Apple's Command Line Tools with xcode-select --install in Terminal."
                : 'Downloaded from the official python-build-standalone releases on GitHub. '
                    'It lives inside the sandbox and never changes your system.',
            style: TextStyle(color: tokens.subtle, fontSize: 13.5),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (Runtimes.canDownloadPython)
              FilledButton.icon(
                onPressed: _task != null
                    ? null
                    : () => _doing('Downloading Python…', () async {
                          await rt.downloadPython(onProgress: _progressCb);
                          await _refresh();
                        }),
                icon: const Icon(Icons.download_rounded),
                label: Text(_pyDownloaded ? 'Download again (newest)' : 'Download Python'),
              ),
            if (!_hasEnv && _pyPath != null)
              OutlinedButton.icon(
                onPressed: _task != null
                    ? null
                    : () => _doing('Setting up packages…', () async {
                          await rt.createEnvironment();
                          await _refresh();
                        }),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Set up packages'),
              ),
            if (_pyDownloaded || _hasEnv)
              TextButton.icon(
                onPressed: _task != null
                    ? null
                    : () async {
                        if (!await _confirm('Remove Python?',
                            'CodeNote\'s downloaded Python and all installed packages are removed. Your notes stay.', 'Remove')) {
                          return;
                        }
                        await _doing('Removing…', () async {
                          await rt.removeDownloadedPython();
                          setState(() => _packages = const []);
                          await _refresh();
                        });
                      },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Remove'),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _packagesCard() {
    final tokens = context.tokens;
    final color = Theme.of(context).colorScheme;
    final outdated = _packages.where((p) => p.outdated).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _pkgInput,
                style: monoStyle(context, size: 14),
                decoration: const InputDecoration(hintText: 'pip install …  e.g. yt-dlp fastapi uvicorn', isDense: true),
                onSubmitted: (_) => _install(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _task != null ? null : _install, child: const Text('Install')),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final name in ['yt-dlp', 'requests', 'fastapi', 'uvicorn', 'numpy', 'rich'])
              ActionChip(
                label: Text(name, style: monoStyle(context, size: 12)),
                onPressed: _task != null
                    ? null
                    : () {
                        _pkgInput.text = name;
                        _install();
                      },
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Text('${_packages.length} installed', style: TextStyle(color: tokens.subtle)),
            if (_checkedUpdates) ...[
              const SizedBox(width: 8),
              Text(outdated == 0 ? '· all up to date' : '· $outdated can update',
                  style: TextStyle(color: outdated == 0 ? tokens.success : tokens.pin)),
            ],
            const Spacer(),
            TextButton(
              onPressed: _task != null ? null : () => _loadPackages(updates: true),
              child: const Text('Check for updates'),
            ),
            if (outdated > 0)
              FilledButton.tonal(
                onPressed: _task != null ? null : _updateAll,
                child: const Text('Update all'),
              ),
          ]),
          for (final pkg in _packages)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(pkg.name, style: monoStyle(context, size: 13.5)),
              subtitle: Text(pkg.outdated ? '${pkg.version} → ${pkg.latest}' : pkg.version,
                  style: monoStyle(context, size: 12, color: pkg.outdated ? tokens.pin : tokens.subtle)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (pkg.outdated)
                  IconButton(
                    tooltip: 'Update',
                    icon: const Icon(Icons.upgrade_rounded),
                    onPressed: _task != null ? null : () => _pip('Updating ${pkg.name}…', ['install', '--upgrade', pkg.name]),
                  ),
                if (!{'pip', 'setuptools', 'wheel'}.contains(pkg.name.toLowerCase()))
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: _task != null ? null : () => _pip('Removing ${pkg.name}…', ['uninstall', '-y', pkg.name]),
                  ),
              ]),
            ),
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: tokens.codeBackground, borderRadius: BorderRadius.circular(10)),
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  _log.map((l) => l.startsWith(RunningProcess.errorMark) ? l.substring(1) : l).join('\n'),
                  style: monoStyle(context, size: 12, color: color.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _shellCard() {
    final tokens = context.tokens;
    final name = _shell == null
        ? 'Bash: not set up'
        : Platform.isAndroid
            ? "Shell: Android's built-in sh"
            : _busyboxDownloaded && Platform.isWindows
                ? 'Bash: BusyBox (downloaded)'
                : 'Bash: ${_shell!.$1}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Image.asset('assets/languages/bash.png', width: 26, height: 26),
            const SizedBox(width: 10),
            Expanded(child: Text(name, style: Theme.of(context).textTheme.titleMedium)),
          ]),
          if (Runtimes.canDownloadBusybox) ...[
            const SizedBox(height: 8),
            Text(
              'Windows has no Bash. CodeNote can download BusyBox from frippery.org (open source, about 1 MB): '
              'a Bash-like shell with the usual commands. Git Bash is used too if you have it.',
              style: TextStyle(color: tokens.subtle, fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              FilledButton.icon(
                onPressed: _task != null
                    ? null
                    : () => _doing('Downloading BusyBox…', () async {
                          await rt.downloadBusybox(onProgress: _progressCb);
                          await _refresh(packages: false);
                        }),
                icon: const Icon(Icons.download_rounded),
                label: Text(_busyboxDownloaded ? 'Download again (newest)' : 'Download Bash (BusyBox)'),
              ),
              if (_busyboxDownloaded)
                TextButton(
                  onPressed: () async {
                    await rt.removeBusybox();
                    await _refresh(packages: false);
                  },
                  child: const Text('Remove'),
                ),
            ]),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TerminalPage())),
              icon: const Icon(Icons.terminal_rounded),
              label: const Text('Open terminal'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _runningCard() {
    final runs = RunManager.instance.running;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (runs.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nothing is running.')),
          for (final s in runs)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.circle, size: 10, color: context.tokens.success),
              title: Text(s.title.isEmpty ? 'Untitled note' : s.title),
              subtitle: Text('since ${TimeOfDay.fromDateTime(s.startedAt).format(context)}'),
              trailing: TextButton(onPressed: s.stop, child: const Text('Stop')),
            ),
          if (runs.length > 1)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(onPressed: RunManager.instance.stopAll, child: const Text('Stop all')),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Runtimes and sandbox'),
        // Always visible, wherever you've scrolled.
        bottom: _task == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(34),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(_task!,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: monoStyle(context, size: 12)),
                      ),
                      if (_progress != null)
                        Text('${(_progress! * 100).round()}%', style: monoStyle(context, size: 12, color: context.tokens.success)),
                    ]),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: _progress, minHeight: 4, borderRadius: BorderRadius.circular(2)),
                  ]),
                ),
              ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              _section('sandbox', [_sandboxCard()]),
              _section('running now', [_runningCard()]),
              _section('python', [_pythonCard()]),
              if (_hasEnv) _section('python packages', [_packagesCard()]),
              if (Runtimes.nodeSupported) _section('javascript', [_nodeCard()]),
              if (Runtimes.dartSupported) _section('dart', [_dartCard()]),
              _section('shell', [_shellCard()]),
              _section('sandbox files', [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.delete_sweep_outlined),
                    title: const Text('Delete all sandbox files'),
                    subtitle: const Text('Files your scripts made. Downloaded Python and packages stay.'),
                    onTap: () async {
                      if (RunManager.instance.running.isNotEmpty) {
                        _snack('Stop running code first.');
                        return;
                      }
                      if (!await _confirm('Delete all sandbox files?',
                          'Everything scripts saved in every sandbox folder is deleted. Your notes stay.', 'Delete')) {
                        return;
                      }
                      await sb.clearFiles();
                      _snack('Sandbox files deleted.');
                    },
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
