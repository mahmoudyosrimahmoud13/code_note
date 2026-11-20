import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/services/log_service.dart';
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

  Future<RunningProcess> pip(List<String> args) async {
    final py = await venvPython();
    if (!await File(py).exists()) {
      throw RuntimeException('Set up Python first.');
    }
    final runtimes = await Sandbox.instance.runtimesDir();
    return start(py, ['-m', 'pip', ...args],
        workDir: runtimes, extraWritable: [runtimes.path], extraPath: [await _venvBin()]);
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
  }) async {
    final env = await Sandbox.instance.environment(workDir,
        extraPath: [...extraPath, ...await toolPaths()]);
    // CodeNote's own Python lives in the sandbox too, so notes can
    // `pip install` what they need without touching the system.
    final runtimes = (await Sandbox.instance.runtimesDir()).path;
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

    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(controller.add, onDone: done);
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((l) => controller.add('${RunningProcess.errorMark}$l'), onDone: done);
    LogService().log('Runner: [START] ${p.basename(executable)} in ${workDir.path}');
    return RunningProcess(process, controller.stream, process.exitCode);
  }

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
