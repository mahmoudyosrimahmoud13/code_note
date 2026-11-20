import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../notes/domain/entities/language.dart';
import 'runtimes.dart';
import 'sandbox.dart';

/// Runs Python, Bash and PowerShell code blocks inside the note's sandbox.
class CodeRunner {
  CodeRunner._();

  /// Languages that get a ▶ Run button on this device.
  static bool canRun(Language language) {
    if (kIsWeb || !Sandbox.supported) return false;
    switch (language) {
      case Language.python:
        return Runtimes.pythonSupported;
      case Language.bash:
        return true;
      case Language.powershell:
        return Platform.isWindows;
      default:
        return false;
    }
  }

  static String _fileName(Language language) => switch (language) {
        Language.python => 'run.py',
        Language.powershell => 'run.ps1',
        _ => 'run.sh',
      };

  /// Starts [code] in the sandbox [spaceKey] (see [Sandbox.keyFor]). Throws [RuntimeException] with a
  /// plain message when something needed is missing.
  static Future<RunningProcess> run({
    required String spaceKey,
    required Language language,
    required String code,
  }) async {
    final allowed = await Sandbox.instance.canRun();
    if (allowed == null) {
      throw RuntimeException(
          'Running code is off on this computer until you allow it in Settings > Runtimes and sandbox.');
    }
    if (allowed == false) throw RuntimeException("Code can't run on this device.");

    final workspace = await Sandbox.instance.space(spaceKey);
    // The script itself sits in a hidden folder, so the Files list only
    // shows what scripts made. Each run gets its own file, so several
    // blocks can run at the same time.
    final helper = Directory(p.join(workspace.path, '.codenote'))..createSync(recursive: true);
    final script = File(p.join(helper.path, '${DateTime.now().microsecondsSinceEpoch}-${_fileName(language)}'));
    await script.writeAsString(code.endsWith('\n') ? code : '$code\n', flush: true);

    switch (language) {
      case Language.python:
        final py = await Runtimes.instance.pythonForRuns();
        if (py == null) {
          throw RuntimeException('Python isn\'t set up yet. Open Settings > Runtimes and sandbox.');
        }
        return Runtimes.instance.start(py, ['-u', script.path], workDir: workspace);
      case Language.powershell:
        return Runtimes.instance.start('powershell.exe',
            ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', script.path],
            workDir: workspace);
      default:
        final shell = await Runtimes.instance.shell();
        if (shell == null) {
          throw RuntimeException('Bash isn\'t set up yet. Open Settings > Runtimes and sandbox.');
        }
        final (exe, pre) = shell;
        return Runtimes.instance.start(exe, [...pre, script.path], workDir: workspace);
    }
  }
}
