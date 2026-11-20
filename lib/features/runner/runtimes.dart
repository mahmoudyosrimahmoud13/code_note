import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/services/log_service.dart';
import 'python_kernel.dart';
import 'sandbox.dart';

class RuntimeException implements Exception {
  RuntimeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A started script or command. Output arrives line by line; stderr lines
/// start with [errorMark] so the UI can color them.
class RunningProcess {
  RunningProcess(this._process, this.lines, this.exitCode);
  final Process _process;
  final Stream<String> lines;
  final Future<int> exitCode;

  static const errorMark = '\u0000';

  static bool isError(String line) =>
      line.startsWith(errorMark) || line.startsWith('$replaceMark$errorMark');

  /// The text of an output line without CodeNote's marks.
  static String plain(String line) => line.replaceAll(replaceMark, '').replaceAll(errorMark, '');

  /// Marks a line that the next line replaces (progress bars that redraw
  /// themselves with a carriage return, like tqdm and pip).
  static const replaceMark = '\u0001';

  /// Splits output into lines. A carriage return without a new line means
  /// "draw over this line", so that line is marked with [replaceMark].
  static Stream<String> splitLines(Stream<List<int>> bytes, {String prefix = ''}) async* {
    final buf = StringBuffer();
    var pendingCr = false; // a \r whose meaning depends on the next character
    await for (final chunk in bytes.transform(const Utf8Decoder(allowMalformed: true))) {
      for (var i = 0; i < chunk.length; i++) {
        final ch = chunk[i];
        if (pendingCr) {
          pendingCr = false;
          if (ch == '\n') {
            // \r\n: an ordinary line end (Windows).
            yield '$prefix$buf';
            buf.clear();
            continue;
          }
          // \r then text: the line is drawn over.
          if (buf.isNotEmpty) yield '$replaceMark$prefix$buf';
          buf.clear();
        }
        if (ch == '\n') {
          yield '$prefix$buf';
          buf.clear();
        } else if (ch == '\r') {
          pendingCr = true;
        } else {
          buf.write(ch);
        }
      }
    }
    if (buf.isNotEmpty) yield '$prefix$buf';
  }

  void stop() {
    _process.kill(ProcessSignal.sigterm);
    Future.delayed(const Duration(seconds: 2), () => _process.kill(ProcessSignal.sigkill));
  }

  void write(String text) {
    try {
      _process.stdin.write(text);
    } catch (_) {}
  }
}

/// A Python package in CodeNote's environment.
class PythonPackage {
  const PythonPackage(this.name, this.version, {this.latest});
  final String name;
  final String version;
  final String? latest;
  bool get outdated => latest != null && latest != version;
}

/// Finds or downloads Python and Bash, and manages the Python packages
/// that scripts can use. Packages live in CodeNote's own environment in
/// the sandbox, so they never change the system Python.
class Runtimes {
  Runtimes._();
  static final Runtimes instance = Runtimes._();

  static bool get _win => Platform.isWindows;

  // ---------- Python ----------

  /// Downloading works where the builds are not blocked by a system
  /// sandbox: Linux and Windows. macOS uses its own Python.
  static bool get canDownloadPython => Platform.isLinux || Platform.isWindows;

  static bool get pythonSupported => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  Future<String> _downloadedPython() async {
    final dir = p.join((await Sandbox.instance.runtimesDir()).path, 'python');
    return _win ? p.join(dir, 'python.exe') : p.join(dir, 'bin', 'python3');
  }

  Future<Directory> _venvDir() async =>
      Directory(p.join((await Sandbox.instance.runtimesDir()).path, 'venv'));

  Future<String> _venvBin() async => p.join((await _venvDir()).path, _win ? 'Scripts' : 'bin');

  Future<String> venvPython() async => p.join(await _venvBin(), _win ? 'python.exe' : 'python');

  /// Python found on the system (not downloaded), or null.
  Future<String?> systemPython() async {
    if (!pythonSupported) return null;
    if (_win) {
      try {
        final r = await Process.run('where', ['python']);
        for (final line in r.stdout.toString().split(RegExp(r'\r?\n'))) {
          final path = line.trim();
          // The WindowsApps "python" only opens the Microsoft Store.
          if (path.isNotEmpty && !path.toLowerCase().contains('windowsapps')) return path;
        }
      } catch (_) {}
      return null;
    }
    for (final c in ['/usr/bin/python3', '/usr/local/bin/python3', '/opt/homebrew/bin/python3']) {
      if (await File(c).exists()) return c;
    }
    return null;
  }

  /// The Python CodeNote builds its environment from: downloaded first.
  Future<String?> basePython() async {
    final downloaded = await _downloadedPython();
    if (await File(downloaded).exists()) return downloaded;
    return systemPython();
  }

  Future<bool> isPythonDownloaded() async => File(await _downloadedPython()).exists();

  Future<bool> hasEnvironment() async => File(await venvPython()).exists();

  /// The Python scripts run with: CodeNote's environment if it exists.
  Future<String?> pythonForRuns() async {
    final venv = await venvPython();
    if (await File(venv).exists()) return venv;
    return basePython();
  }

  Future<String?> pythonVersion() async {
    final py = await pythonForRuns();
    if (py == null) return null;
    try {
      final r = await Process.run(py, ['--version']);
      return '${r.stdout}${r.stderr}'.trim().replaceFirst('Python ', '');
    } catch (_) {
      return null;
    }
  }

  /// Creates CodeNote's own Python environment (with pip).
  Future<void> createEnvironment() async {
    final base = await basePython();
    if (base == null) throw RuntimeException('No Python found. Download it first.');
    final dir = await _venvDir();
    if (await dir.exists()) await dir.delete(recursive: true);
    final r = await Process.run(base, ['-m', 'venv', dir.path]);
    if (r.exitCode != 0) {
      final err = '${r.stderr}'.trim();
      if (err.contains('ensurepip')) {
        throw RuntimeException(
            "Your system Python can't make environments (the python3-venv package is missing). "
            'Press "Download Python" to use CodeNote\'s own Python instead.');
      }
      throw RuntimeException("Couldn't set up Python: $err");
    }
  }

  static String? _pythonTarget() {
    final abi = Abi.current();
    if (abi == Abi.linuxX64) return 'x86_64-unknown-linux-gnu';
    if (abi == Abi.linuxArm64) return 'aarch64-unknown-linux-gnu';
    if (abi == Abi.windowsX64) return 'x86_64-pc-windows-msvc';
    return null;
  }

  /// Picks the right file from a python-build-standalone release.
  static Map<String, dynamic>? pickPythonAsset(List<dynamic> assets, String target) {
    final pattern = RegExp('^cpython-3\\.12\\.\\d+\\+\\d+-${RegExp.escape(target)}-install_only\\.tar\\.gz\$');
    for (final a in assets) {
      if (a is Map<String, dynamic> && pattern.hasMatch(a['name'] as String? ?? '')) return a;
    }
    return null;
  }

  /// Downloads Python 3.12 from the official python-build-standalone
  /// releases on GitHub (astral-sh/python-build-standalone) into the
  /// sandbox, then builds CodeNote's environment from it.
  Future<void> downloadPython({void Function(double progress, String status)? onProgress}) async {
    final target = _pythonTarget();
    if (!canDownloadPython || target == null) {
      throw RuntimeException('Downloading Python isn\'t available on this computer.');
    }
    onProgress?.call(0, 'Finding the newest Python…');
    final rel = await http
        .get(Uri.parse('https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 20));
    if (rel.statusCode != 200) throw RuntimeException('GitHub answered ${rel.statusCode}. Try again later.');
    final assets = (json.decode(rel.body) as Map<String, dynamic>)['assets'] as List? ?? const [];
    final asset = pickPythonAsset(assets, target);
    if (asset == null) throw RuntimeException("Couldn't find a Python build for this computer.");

    final runtimes = await Sandbox.instance.runtimesDir();
    final archive = File(p.join(runtimes.path, 'python-download.tar.gz'));
    await _download(Uri.parse(asset['browser_download_url'] as String), archive,
        (f) => onProgress?.call(f * 0.9, 'Downloading ${asset['name']}…'));

    onProgress?.call(0.92, 'Unpacking…');
    final old = Directory(p.join(runtimes.path, 'python'));
    if (await old.exists()) await old.delete(recursive: true);
    final r = await Process.run('tar', ['-xzf', archive.path, '-C', runtimes.path]);
    await archive.delete();
    if (r.exitCode != 0) throw RuntimeException("Couldn't unpack Python: ${r.stderr}");

    onProgress?.call(0.96, 'Setting up packages…');
    await createEnvironment();
    onProgress?.call(1, 'Python is ready.');
  }

  Future<void> removeDownloadedPython() async {
    final dir = Directory(p.join((await Sandbox.instance.runtimesDir()).path, 'python'));
    if (await dir.exists()) await dir.delete(recursive: true);
    final venv = await _venvDir();
    if (await venv.exists()) await venv.delete(recursive: true);
  }

  // ---------- Packages ----------

  bool? _pipRaw;

  /// pip 24.1+ can report download progress as plain lines
  /// ("Progress 1234 of 5678"), which the Settings page turns into a bar.
  Future<bool> pipReportsProgress() async {
    if (_pipRaw != null) return _pipRaw!;
    try {
      final r = await Process.run(await venvPython(), ['-m', 'pip', '--version']);
      final m = RegExp(r'pip (\d+)\.(\d+)').firstMatch('${r.stdout}');
      final major = int.parse(m!.group(1)!), minor = int.parse(m.group(2)!);
      return _pipRaw = major > 24 || (major == 24 && minor >= 1);
    } catch (_) {
      return _pipRaw = false;
    }
  }

  /// Reads a pip progress line: the fraction done, or null.
  static double? pipProgress(String line) {
    final m = RegExp(r'^Progress (\d+) of (\d+)').firstMatch(line.trim());
    if (m == null) return null;
    final total = int.parse(m.group(2)!);
    return total == 0 ? null : (int.parse(m.group(1)!) / total).clamp(0.0, 1.0);
  }

  Future<RunningProcess> pip(List<String> args) async {
    final py = await venvPython();
    if (!await File(py).exists()) {
      throw RuntimeException('Set up Python first.');
    }
    final runtimes = await Sandbox.instance.runtimesDir();
    return start(py, ['-m', 'pip', ...args],
        workDir: runtimes, extraWritable: [runtimes.path], extraPath: [await _venvBin()], richPython: false);
  }

  Future<String> _pipJson(List<String> args) async {
    final proc = await pip(args);
    final out = StringBuffer();
    await for (final line in proc.lines) {
      if (!line.startsWith(RunningProcess.errorMark)) out.writeln(line);
    }
    await proc.exitCode;
    return out.toString();
  }

  static List<PythonPackage> parsePackages(String jsonText, {bool outdated = false}) {
    final start = jsonText.indexOf('[');
    if (start < 0) return const [];
    try {
      final list = json.decode(jsonText.substring(start)) as List;
      return [
        for (final e in list.whereType<Map>())
          PythonPackage(e['name'].toString(), e['version'].toString(),
              latest: outdated ? e['latest_version']?.toString() : null),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (_) {
      return const [];
    }
  }

  /// Installed packages, with the newer version when one exists.
  Future<List<PythonPackage>> packages({bool checkUpdates = false}) async {
    if (!await hasEnvironment()) return const [];
    final all = parsePackages(await _pipJson(['list', '--format=json']));
    if (!checkUpdates) return all;
    final newer = {
      for (final pkg in parsePackages(await _pipJson(['list', '--outdated', '--format=json']), outdated: true))
        pkg.name.toLowerCase(): pkg.latest,
    };
    return [for (final pkg in all) PythonPackage(pkg.name, pkg.version, latest: newer[pkg.name.toLowerCase()])];
  }

  /// A safe package name, or null ("yt-dlp", "requests==2.32", "numpy>=2").
  static String? cleanPackageName(String input) {
    final t = input.trim();
    if (RegExp(r'^[A-Za-z0-9][A-Za-z0-9._\-\[\],]*([=<>!~]=?[A-Za-z0-9.*+\-]+)?$').hasMatch(t)) return t;
    return null;
  }

  // ---------- Node.js ----------

  static bool get nodeSupported => Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  static bool get canDownloadNode => _nodeTarget() != null;

  static String? _nodeTarget() {
    final abi = Abi.current();
    if (abi == Abi.linuxX64) return 'linux-x64';
    if (abi == Abi.linuxArm64) return 'linux-arm64';
    if (abi == Abi.windowsX64) return 'win-x64';
    return null;
  }

  Future<Directory> _nodeDir() async => Directory(p.join((await Sandbox.instance.runtimesDir()).path, 'node'));

  Future<String> _downloadedNode() async {
    final dir = (await _nodeDir()).path;
    return _win ? p.join(dir, 'node.exe') : p.join(dir, 'bin', 'node');
  }

  Future<bool> isNodeDownloaded() async => File(await _downloadedNode()).exists();

  Future<String?> systemNode() async {
    if (!nodeSupported) return null;
    if (_win) return _where('node');
    for (final c in ['/usr/bin/node', '/usr/local/bin/node', '/opt/homebrew/bin/node']) {
      if (await File(c).exists()) return c;
    }
    return null;
  }

  Future<String?> nodeForRuns() async {
    final d = await _downloadedNode();
    if (await File(d).exists()) return d;
    return systemNode();
  }

  String? _nodeVersionCache;

  Future<String?> nodeVersion() async {
    final node = await nodeForRuns();
    if (node == null) return null;
    try {
      final r = await Process.run(node, ['--version']);
      return _nodeVersionCache = r.stdout.toString().trim().replaceFirst('v', '');
    } catch (_) {
      return null;
    }
  }

  /// Extra Node flags for TypeScript: Node 22 needs a switch, 23.6+ runs
  /// .ts files as they are. Null means this Node is too old for TypeScript.
  Future<List<String>?> typeScriptFlags() async {
    final v = _nodeVersionCache ?? await nodeVersion();
    final major = int.tryParse((v ?? '').split('.').first) ?? 0;
    if (major < 22) return null;
    return major == 22 ? const ['--experimental-strip-types', '--no-warnings'] : const ['--no-warnings'];
  }

  /// npm's own script, run with our node (works the same everywhere).
  Future<String?> _npmCli() async {
    final node = await nodeForRuns();
    if (node == null) return null;
    final base = p.dirname(node);
    for (final c in [
      p.join(base, 'node_modules', 'npm', 'bin', 'npm-cli.js'),
      p.join(base, '..', 'lib', 'node_modules', 'npm', 'bin', 'npm-cli.js'),
      '/usr/share/nodejs/npm/bin/npm-cli.js',
      '/usr/lib/node_modules/npm/bin/npm-cli.js',
    ]) {
      if (await File(c).exists()) return p.normalize(c);
    }
    return null;
  }

  Future<String> _npmGlobal() async => p.join((await Sandbox.instance.runtimesDir()).path, 'npm-global');

  /// Newest LTS Node.js from nodejs.org, into the sandbox.
  Future<void> downloadNode({void Function(double progress, String status)? onProgress}) async {
    final target = _nodeTarget();
    if (target == null) throw RuntimeException("Downloading Node.js isn't available on this computer.");
    onProgress?.call(0, 'Finding the newest Node.js LTS…');
    final res = await http.get(Uri.parse('https://nodejs.org/dist/index.json')).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw RuntimeException('nodejs.org answered ${res.statusCode}. Try again later.');
    final lts = (json.decode(res.body) as List).cast<Map<String, dynamic>>().firstWhere(
          (r) => r['lts'] != false && r['lts'] != null,
          orElse: () => throw RuntimeException("Couldn't find a Node.js LTS release."),
        );
    final version = lts['version'] as String;
    final name = 'node-$version-$target';
    final file = _win ? '$name.zip' : '$name.tar.xz';
    final runtimes = await Sandbox.instance.runtimesDir();
    final archive = File(p.join(runtimes.path, file));
    await _download(Uri.parse('https://nodejs.org/dist/$version/$file'), archive,
        (f) => onProgress?.call(f * 0.9, 'Downloading Node.js $version…'));
    onProgress?.call(0.92, 'Unpacking…');
    final dir = await _nodeDir();
    if (await dir.exists()) await dir.delete(recursive: true);
    await _extract(archive, runtimes);
    await Directory(p.join(runtimes.path, name)).rename(dir.path);
    await _makeRunnable(Directory(p.join(dir.path, 'bin')));
    onProgress?.call(1, 'Node.js $version is ready.');
  }

  Future<void> removeNode() async {
    for (final d in [await _nodeDir(), Directory(await _npmGlobal())]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  }

  /// Runs npm inside the sandbox, with global packages kept in the sandbox.
  Future<RunningProcess> npm(List<String> args) async {
    final node = await nodeForRuns();
    final cli = await _npmCli();
    if (node == null || cli == null) throw RuntimeException('Set up Node.js first.');
    final runtimes = await Sandbox.instance.runtimesDir();
    return start(node, [cli, ...args], workDir: runtimes, richPython: false);
  }

  /// Global npm packages in the sandbox, with newer versions when known.
  Future<List<PythonPackage>> npmPackages({bool checkUpdates = false}) async {
    if (await nodeForRuns() == null) return const [];
    Future<String> out(List<String> args) async {
      final proc = await npm(args);
      final b = StringBuffer();
      await for (final l in proc.lines) {
        if (!l.startsWith(RunningProcess.errorMark)) b.writeln(l);
      }
      await proc.exitCode;
      return b.toString();
    }

    final list = parseNpmList(await out(['ls', '-g', '--json', '--depth=0']));
    if (!checkUpdates) return list;
    final newer = parseNpmOutdated(await out(['outdated', '-g', '--json']));
    return [for (final pkg in list) PythonPackage(pkg.name, pkg.version, latest: newer[pkg.name])];
  }

  static List<PythonPackage> parseNpmList(String text) {
    try {
      final deps = (json.decode(text.substring(text.indexOf('{'))) as Map)['dependencies'] as Map? ?? {};
      return [
        for (final e in deps.entries)
          if (e.key != 'npm' && e.key != 'corepack') PythonPackage(e.key.toString(), '${(e.value as Map)['version'] ?? ''}'),
      ]..sort((a, b) => a.name.compareTo(b.name));
    } catch (_) {
      return const [];
    }
  }

  static Map<String, String> parseNpmOutdated(String text) {
    try {
      final m = json.decode(text.substring(text.indexOf('{'))) as Map;
      return {for (final e in m.entries) e.key.toString(): '${(e.value as Map)['latest']}'};
    } catch (_) {
      return const {};
    }
  }

  // ---------- Dart ----------

  static bool get dartSupported => Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  static bool get canDownloadDart => _dartTarget() != null;

  static String? _dartTarget() {
    final abi = Abi.current();
    if (abi == Abi.linuxX64) return 'linux-x64';
    if (abi == Abi.linuxArm64) return 'linux-arm64';
    if (abi == Abi.windowsX64) return 'windows-x64';
    return null;
  }

  Future<String> _downloadedDart() async =>
      p.join((await Sandbox.instance.runtimesDir()).path, 'dart-sdk', 'bin', _win ? 'dart.exe' : 'dart');

  Future<bool> isDartDownloaded() async => File(await _downloadedDart()).exists();

  Future<String?> systemDart() async {
    if (!dartSupported) return null;
    if (_win) return _where('dart');
    for (final c in ['/usr/lib/dart/bin/dart', '/usr/bin/dart', '/usr/local/bin/dart', '/opt/homebrew/bin/dart']) {
      if (await File(c).exists()) return c;
    }
    return null;
  }

  Future<String?> dartForRuns() async {
    final d = await _downloadedDart();
    if (await File(d).exists()) return d;
    return systemDart();
  }

  Future<String?> dartVersion() async {
    final dart = await dartForRuns();
    if (dart == null) return null;
    try {
      final r = await Process.run(dart, ['--version']);
      final m = RegExp(r'(\d+\.\d+\.\d+\S*)').firstMatch('${r.stdout}${r.stderr}');
      return m?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// The stable Dart SDK from Google's official Dart archive, into the sandbox.
  Future<void> downloadDart({void Function(double progress, String status)? onProgress}) async {
    final target = _dartTarget();
    if (target == null) throw RuntimeException("Downloading Dart isn't available on this computer.");
    const base = 'https://storage.googleapis.com/dart-archive/channels/stable/release/latest';
    onProgress?.call(0, 'Finding the newest Dart…');
    String version = 'latest';
    try {
      final v = await http.get(Uri.parse('$base/VERSION')).timeout(const Duration(seconds: 15));
      version = (json.decode(v.body) as Map)['version']?.toString() ?? version;
    } catch (_) {}
    final runtimes = await Sandbox.instance.runtimesDir();
    final archive = File(p.join(runtimes.path, 'dart-sdk.zip'));
    await _download(Uri.parse('$base/sdk/dartsdk-$target-release.zip'), archive,
        (f) => onProgress?.call(f * 0.9, 'Downloading Dart $version…'));
    onProgress?.call(0.92, 'Unpacking…');
    final old = Directory(p.join(runtimes.path, 'dart-sdk'));
    if (await old.exists()) await old.delete(recursive: true);
    await _extract(archive, runtimes);
    await _makeRunnable(Directory(p.join(runtimes.path, 'dart-sdk', 'bin')));
    onProgress?.call(0.98, 'Turning off Dart analytics…');
    try {
      await Process.run(await _downloadedDart(), ['--disable-analytics'],
          environment: await Sandbox.instance.environment(runtimes));
    } catch (_) {}
    onProgress?.call(1, 'Dart $version is ready.');
  }

  Future<void> removeDart() async {
    final d = Directory(p.join((await Sandbox.instance.runtimesDir()).path, 'dart-sdk'));
    if (await d.exists()) await d.delete(recursive: true);
  }

  // ---------- Helpers ----------

  Future<String?> _where(String name) async {
    try {
      final r = await Process.run('where', [name]);
      for (final line in r.stdout.toString().split(RegExp(r'\r?\n'))) {
        final path = line.trim();
        if (path.isNotEmpty && !path.toLowerCase().contains('windowsapps')) return path;
      }
    } catch (_) {}
    return null;
  }

  /// Unpacks .tar.gz, .tar.xz and .zip files with the system's own tools,
  /// then deletes the archive.
  Future<void> _extract(File archive, Directory into) async {
    final name = archive.path.toLowerCase();
    ProcessResult r;
    if (!name.endsWith('.zip') || _win) {
      // Windows 10+ tar (bsdtar) also handles .zip.
      r = await Process.run('tar', ['-xf', archive.path, '-C', into.path]);
    } else {
      r = await Process.run('unzip', ['-q', '-o', archive.path, '-d', into.path]).catchError(
          (_) => ProcessResult(0, 127, '', 'no unzip'));
      if (r.exitCode != 0) {
        final py = await basePython() ?? '/usr/bin/python3';
        r = await Process.run(py, ['-m', 'zipfile', '-e', archive.path, into.path]);
      }
    }
    if (await archive.exists()) await archive.delete();
    if (r.exitCode != 0) {
      throw RuntimeException("Couldn't unpack ${p.basename(archive.path)}: ${r.stderr}".trim());
    }
  }

  /// Some unpackers drop the "can run" flag; put it back on Linux and macOS.
  Future<void> _makeRunnable(Directory bin) async {
    if (_win || !await bin.exists()) return;
    await Process.run('chmod', ['-R', 'a+rx', bin.path]);
  }

  /// A safe npm package name, or null ("prettier", "@angular/cli@17").
  static String? cleanNpmName(String input) {
    final t = input.trim();
    if (RegExp(r'^(@[a-z0-9][a-z0-9._~-]*/)?[a-z0-9][a-z0-9._~-]*(@[A-Za-z0-9.^~<>=*_-]+)?$').hasMatch(t)) return t;
    return null;
  }

  // ---------- Shell ----------

  Future<String> _busybox() async =>
      p.join((await Sandbox.instance.runtimesDir()).path, 'busybox', 'busybox.exe');

  /// The shell for Bash blocks and the Terminal, as (program, args before
  /// the script). Null if none is available yet.
  Future<(String, List<String>)?> shell() async {
    if (Platform.isAndroid) return ('/system/bin/sh', const <String>[]);
    if (Platform.isLinux || Platform.isMacOS) {
      for (final c in ['/bin/bash', '/usr/bin/bash', '/bin/sh']) {
        if (await File(c).exists()) return (c, const <String>[]);
      }
      return null;
    }
    if (_win) {
      final bb = await _busybox();
      if (await File(bb).exists()) return (bb, const ['bash']);
      for (final c in [r'C:\Program Files\Git\bin\bash.exe', r'C:\Program Files (x86)\Git\bin\bash.exe']) {
        if (await File(c).exists()) return (c, const <String>[]);
      }
    }
    return null;
  }

  static bool get canDownloadBusybox => Platform.isWindows;

  Future<bool> isBusyboxDownloaded() async => File(await _busybox()).exists();

  /// BusyBox for Windows (frippery.org): a small, open source Bash-like
  /// shell with the usual commands (ls, grep, sed, curl-like wget, …).
  Future<void> downloadBusybox({void Function(double progress, String status)? onProgress}) async {
    final file = File(await _busybox());
    await file.parent.create(recursive: true);
    await _download(Uri.parse('https://frippery.org/files/busybox/busybox64.exe'), file,
        (f) => onProgress?.call(f, 'Downloading BusyBox…'));
    onProgress?.call(1, 'Bash is ready.');
  }

  Future<void> removeBusybox() async {
    final f = File(await _busybox());
    if (await f.exists()) await f.delete();
  }

  // ---------- Starting processes ----------

  /// Directories every run puts first on PATH: CodeNote's Python tools
  /// (so `yt-dlp` and `pip` work in Bash) and BusyBox on Windows.
  Future<List<String>> toolPaths() async {
    final paths = <String>[];
    if (await hasEnvironment()) paths.add(await _venvBin());
    final node = await nodeForRuns();
    if (node != null) {
      paths.add(p.dirname(node));
      final global = await _npmGlobal();
      paths.add(_win ? global : p.join(global, 'bin'));
    }
    final dart = await dartForRuns();
    if (dart != null) paths.add(p.dirname(dart));
    if (_win && await isBusyboxDownloaded()) paths.add(p.dirname(await _busybox()));
    return paths;
  }

  /// Starts [executable] inside the sandbox in [workDir].
  Future<RunningProcess> start(
    String executable,
    List<String> args, {
    required Directory workDir,
    List<String> extraWritable = const [],
    List<String> extraPath = const [],
    Map<String, String> extraEnv = const {},
    bool richPython = true,
  }) async {
    // Jupyter-style output for any Python started here, even from Bash or
    // the terminal: plots and tables show in CodeNote's output.
    final helpers = richPython ? await writePythonHelpers(workDir) : null;
    final env = await Sandbox.instance.environment(workDir,
        extraPath: [...extraPath, ...await toolPaths()]);
    final runtimes = (await Sandbox.instance.runtimesDir()).path;
    final cache = p.join(p.dirname(runtimes), 'cache');
    env.addAll({
      'NPM_CONFIG_PREFIX': await _npmGlobal(),
      'NPM_CONFIG_CACHE': p.join(cache, 'npm'),
      'NPM_CONFIG_UPDATE_NOTIFIER': 'false',
      'NPM_CONFIG_FUND': 'false',
      'PUB_CACHE': p.join(runtimes, 'pub-cache'),
      if (helpers != null) ...{
        // Python plots go into the output instead of a window.
        'MPLBACKEND': 'module://codenote_mpl',
        'PYTHONPATH': helpers.path,
        'CODENOTE_OUT': p.join(workDir.path, '.codenote', 'out'),
      },
      ...extraEnv,
    });
    // CodeNote's own Python lives in the sandbox too, so notes can
    // `pip install` what they need without touching the system.
    final (cmd, cmdArgs) = await Sandbox.instance.command(executable, args,
        writable: workDir, extraWritable: {...extraWritable, runtimes}.toList());
    final Process process;
    try {
      process = await Process.start(cmd, cmdArgs,
          workingDirectory: workDir.path, environment: env, includeParentEnvironment: false);
    } on ProcessException catch (e) {
      throw RuntimeException("Couldn't start ${p.basename(executable)}: ${e.message}");
    }
    final controller = StreamController<String>();
    var open = 2;
    void done() {
      if (--open == 0) controller.close();
    }

    RunningProcess.splitLines(process.stdout).listen(controller.add, onDone: done);
    RunningProcess.splitLines(process.stderr, prefix: RunningProcess.errorMark)
        .listen(controller.add, onDone: done);
    LogService().log('Runner: [START] ${p.basename(executable)} in ${workDir.path}');
    return RunningProcess(process, controller.stream, process.exitCode);
  }

  /// Downloads [url] into [to], reporting 0..1 progress.
  Future<void> downloadFile(Uri url, File to, void Function(double fraction) onProgress) =>
      _download(url, to, onProgress);

  Future<void> _download(Uri url, File to, void Function(double fraction) onProgress) async {
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', url)).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw RuntimeException('Download failed (${res.statusCode}).');
      final total = res.contentLength ?? 0;
      var got = 0;
      final sink = to.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
    } on TimeoutException {
      throw RuntimeException('The download timed out. Check your internet connection.');
    } on SocketException {
      throw RuntimeException("Couldn't reach the download server. Check your internet connection.");
    } finally {
      client.close();
    }
  }
}
