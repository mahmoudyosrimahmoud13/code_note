// The one place that knows everything about each code language:
// its name, file extension, comment style and syntax colors.
// To add a language: add it to the Language enum, then add one entry here.

// Each grammar gets its own prefix so short names (r, less, xml) can't clash.
import 'package:highlight/highlight_core.dart' show Mode;

import 'package:highlight/languages/arduino.dart' as hl_arduino;
import 'package:highlight/languages/armasm.dart' as hl_armasm;
import 'package:highlight/languages/bash.dart' as hl_bash;
import 'package:highlight/languages/clojure.dart' as hl_clojure;
import 'package:highlight/languages/cmake.dart' as hl_cmake;
import 'package:highlight/languages/cpp.dart' as hl_cpp;
import 'package:highlight/languages/cs.dart' as hl_cs;
import 'package:highlight/languages/css.dart' as hl_css;
import 'package:highlight/languages/dart.dart' as hl_dart;
import 'package:highlight/languages/django.dart' as hl_django;
import 'package:highlight/languages/dockerfile.dart' as hl_dockerfile;
import 'package:highlight/languages/elixir.dart' as hl_elixir;
import 'package:highlight/languages/erlang.dart' as hl_erlang;
import 'package:highlight/languages/fortran.dart' as hl_fortran;
import 'package:highlight/languages/fsharp.dart' as hl_fsharp;
import 'package:highlight/languages/go.dart' as hl_go;
import 'package:highlight/languages/gradle.dart' as hl_gradle;
import 'package:highlight/languages/graphql.dart' as hl_graphql;
import 'package:highlight/languages/groovy.dart' as hl_groovy;
import 'package:highlight/languages/haskell.dart' as hl_haskell;
import 'package:highlight/languages/htmlbars.dart' as hl_htmlbars;
import 'package:highlight/languages/ini.dart' as hl_ini;
import 'package:highlight/languages/java.dart' as hl_java;
import 'package:highlight/languages/javascript.dart' as hl_javascript;
import 'package:highlight/languages/json.dart' as hl_json;
import 'package:highlight/languages/julia.dart' as hl_julia;
import 'package:highlight/languages/kotlin.dart' as hl_kotlin;
import 'package:highlight/languages/less.dart' as hl_less;
import 'package:highlight/languages/lua.dart' as hl_lua;
import 'package:highlight/languages/makefile.dart' as hl_makefile;
import 'package:highlight/languages/markdown.dart' as hl_markdown;
import 'package:highlight/languages/matlab.dart' as hl_matlab;
import 'package:highlight/languages/nginx.dart' as hl_nginx;
import 'package:highlight/languages/objectivec.dart' as hl_objectivec;
import 'package:highlight/languages/ocaml.dart' as hl_ocaml;
import 'package:highlight/languages/perl.dart' as hl_perl;
import 'package:highlight/languages/pgsql.dart' as hl_pgsql;
import 'package:highlight/languages/php.dart' as hl_php;
import 'package:highlight/languages/plaintext.dart' as hl_plaintext;
import 'package:highlight/languages/powershell.dart' as hl_powershell;
import 'package:highlight/languages/protobuf.dart' as hl_protobuf;
import 'package:highlight/languages/python.dart' as hl_python;
import 'package:highlight/languages/r.dart' as hl_r;
import 'package:highlight/languages/ruby.dart' as hl_ruby;
import 'package:highlight/languages/rust.dart' as hl_rust;
import 'package:highlight/languages/scala.dart' as hl_scala;
import 'package:highlight/languages/scss.dart' as hl_scss;
import 'package:highlight/languages/solidity.dart' as hl_solidity;
import 'package:highlight/languages/sql.dart' as hl_sql;
import 'package:highlight/languages/swift.dart' as hl_swift;
import 'package:highlight/languages/typescript.dart' as hl_typescript;
import 'package:highlight/languages/vbnet.dart' as hl_vbnet;
import 'package:highlight/languages/verilog.dart' as hl_verilog;
import 'package:highlight/languages/vhdl.dart' as hl_vhdl;
import 'package:highlight/languages/x86asm.dart' as hl_x86asm;
import 'package:highlight/languages/xml.dart' as hl_xml;
import 'package:highlight/languages/yaml.dart' as hl_yaml;

import '../../features/notes/domain/entities/language.dart';

class LanguageInfo {
  const LanguageInfo({
    required this.label,
    required this.short,
    required this.extension,
    required this.commentStart,
    this.commentEnd = '',
    required this.mode,
    this.otherExtensions = const [],
  });

  /// Full name, for menus ("TypeScript").
  final String label;

  /// Short lowercase name, for cards ("ts").
  final String short;

  /// File extension without the dot, used when sharing as a file.
  final String extension;
  final String commentStart;
  final String commentEnd;

  /// Syntax highlighting grammar.
  final Mode mode;

  /// More extensions recognized when a file is shared into CodeNote.
  final List<String> otherExtensions;
}

final Map<Language, LanguageInfo> languages = {
  Language.none: LanguageInfo(label: 'Plain text', short: 'text', extension: 'txt', commentStart: '', commentEnd: '', mode: hl_plaintext.plaintext, otherExtensions: const []),
  Language.python: LanguageInfo(label: 'Python', short: 'python', extension: 'py', commentStart: '# ', commentEnd: '', mode: hl_python.python, otherExtensions: const ['pyw']),
  Language.cSharp: LanguageInfo(label: 'C#', short: 'c#', extension: 'cs', commentStart: '// ', commentEnd: '', mode: hl_cs.cs, otherExtensions: const []),
  Language.dart: LanguageInfo(label: 'Dart', short: 'dart', extension: 'dart', commentStart: '// ', commentEnd: '', mode: hl_dart.dart, otherExtensions: const []),
  Language.go: LanguageInfo(label: 'Go', short: 'go', extension: 'go', commentStart: '// ', commentEnd: '', mode: hl_go.go, otherExtensions: const []),
  Language.java: LanguageInfo(label: 'Java', short: 'java', extension: 'java', commentStart: '// ', commentEnd: '', mode: hl_java.java, otherExtensions: const []),
  Language.javaScript: LanguageInfo(label: 'JavaScript', short: 'js', extension: 'js', commentStart: '// ', commentEnd: '', mode: hl_javascript.javascript, otherExtensions: const ['mjs', 'cjs', 'jsx']),
  Language.typeScript: LanguageInfo(label: 'TypeScript', short: 'ts', extension: 'ts', commentStart: '// ', commentEnd: '', mode: hl_typescript.typescript, otherExtensions: const ['tsx']),
  Language.cpp: LanguageInfo(label: 'C++', short: 'c++', extension: 'cpp', commentStart: '// ', commentEnd: '', mode: hl_cpp.cpp, otherExtensions: const ['cxx', 'cc', 'hpp', 'hh']),
  Language.php: LanguageInfo(label: 'PHP', short: 'php', extension: 'php', commentStart: '// ', commentEnd: '', mode: hl_php.php, otherExtensions: const []),
  Language.arduino: LanguageInfo(label: 'Arduino', short: 'arduino', extension: 'ino', commentStart: '// ', commentEnd: '', mode: hl_arduino.arduino, otherExtensions: const []),
  Language.armAssembly: LanguageInfo(label: 'ARM Assembly', short: 'arm asm', extension: 's', commentStart: '@ ', commentEnd: '', mode: hl_armasm.armasm, otherExtensions: const []),
  Language.x86Assembly: LanguageInfo(label: 'x86 Assembly', short: 'x86 asm', extension: 'asm', commentStart: '; ', commentEnd: '', mode: hl_x86asm.x86Asm, otherExtensions: const []),
  Language.bash: LanguageInfo(label: 'Bash', short: 'bash', extension: 'sh', commentStart: '# ', commentEnd: '', mode: hl_bash.bash, otherExtensions: const ['bash', 'zsh']),
  Language.django: LanguageInfo(label: 'Django', short: 'django', extension: 'py', commentStart: '# ', commentEnd: '', mode: hl_django.django, otherExtensions: const []),
  Language.html: LanguageInfo(label: 'HTML', short: 'html', extension: 'html', commentStart: '<!-- ', commentEnd: ' -->', mode: hl_htmlbars.htmlbars, otherExtensions: const ['htm']),
  Language.css: LanguageInfo(label: 'CSS', short: 'css', extension: 'css', commentStart: '/* ', commentEnd: ' */', mode: hl_css.css, otherExtensions: const []),
  Language.docker: LanguageInfo(label: 'Dockerfile', short: 'docker', extension: 'Dockerfile', commentStart: '# ', commentEnd: '', mode: hl_dockerfile.dockerfile, otherExtensions: const ['dockerfile']),
  Language.kotlin: LanguageInfo(label: 'Kotlin', short: 'kotlin', extension: 'kt', commentStart: '// ', commentEnd: '', mode: hl_kotlin.kotlin, otherExtensions: const ['kts']),
  Language.sql: LanguageInfo(label: 'SQL', short: 'sql', extension: 'sql', commentStart: '-- ', commentEnd: '', mode: hl_sql.sql, otherExtensions: const []),
  Language.pgSql: LanguageInfo(label: 'PostgreSQL', short: 'postgres', extension: 'sql', commentStart: '-- ', commentEnd: '', mode: hl_pgsql.pgsql, otherExtensions: const ['pgsql']),
  Language.json: LanguageInfo(label: 'JSON', short: 'json', extension: 'json', commentStart: '// ', commentEnd: '', mode: hl_json.json, otherExtensions: const []),
  Language.c: LanguageInfo(label: 'C', short: 'c', extension: 'c', commentStart: '// ', commentEnd: '', mode: hl_cpp.cpp, otherExtensions: const ['h']),
  Language.rust: LanguageInfo(label: 'Rust', short: 'rust', extension: 'rs', commentStart: '// ', commentEnd: '', mode: hl_rust.rust, otherExtensions: const []),
  Language.swift: LanguageInfo(label: 'Swift', short: 'swift', extension: 'swift', commentStart: '// ', commentEnd: '', mode: hl_swift.swift, otherExtensions: const []),
  Language.ruby: LanguageInfo(label: 'Ruby', short: 'ruby', extension: 'rb', commentStart: '# ', commentEnd: '', mode: hl_ruby.ruby, otherExtensions: const []),
  Language.r: LanguageInfo(label: 'R', short: 'r', extension: 'r', commentStart: '# ', commentEnd: '', mode: hl_r.r, otherExtensions: const ['R']),
  Language.scala: LanguageInfo(label: 'Scala', short: 'scala', extension: 'scala', commentStart: '// ', commentEnd: '', mode: hl_scala.scala, otherExtensions: const ['sc']),
  Language.lua: LanguageInfo(label: 'Lua', short: 'lua', extension: 'lua', commentStart: '-- ', commentEnd: '', mode: hl_lua.lua, otherExtensions: const []),
  Language.perl: LanguageInfo(label: 'Perl', short: 'perl', extension: 'pl', commentStart: '# ', commentEnd: '', mode: hl_perl.perl, otherExtensions: const ['pm']),
  Language.yaml: LanguageInfo(label: 'YAML', short: 'yaml', extension: 'yaml', commentStart: '# ', commentEnd: '', mode: hl_yaml.yaml, otherExtensions: const ['yml']),
  Language.xml: LanguageInfo(label: 'XML', short: 'xml', extension: 'xml', commentStart: '<!-- ', commentEnd: ' -->', mode: hl_xml.xml, otherExtensions: const ['svg', 'plist']),
  Language.markdown: LanguageInfo(label: 'Markdown', short: 'markdown', extension: 'md', commentStart: '<!-- ', commentEnd: ' -->', mode: hl_markdown.markdown, otherExtensions: const ['markdown']),
  Language.matlab: LanguageInfo(label: 'MATLAB', short: 'matlab', extension: 'm', commentStart: '% ', commentEnd: '', mode: hl_matlab.matlab, otherExtensions: const []),
  Language.haskell: LanguageInfo(label: 'Haskell', short: 'haskell', extension: 'hs', commentStart: '-- ', commentEnd: '', mode: hl_haskell.haskell, otherExtensions: const []),
  Language.elixir: LanguageInfo(label: 'Elixir', short: 'elixir', extension: 'ex', commentStart: '# ', commentEnd: '', mode: hl_elixir.elixir, otherExtensions: const ['exs']),
  Language.objectiveC: LanguageInfo(label: 'Objective-C', short: 'obj-c', extension: 'mm', commentStart: '// ', commentEnd: '', mode: hl_objectivec.objectivec, otherExtensions: const []),
  Language.powershell: LanguageInfo(label: 'PowerShell', short: 'powershell', extension: 'ps1', commentStart: '# ', commentEnd: '', mode: hl_powershell.powershell, otherExtensions: const []),
  Language.makefile: LanguageInfo(label: 'Makefile', short: 'make', extension: 'mk', commentStart: '# ', commentEnd: '', mode: hl_makefile.makefile, otherExtensions: const ['makefile']),
  Language.cmake: LanguageInfo(label: 'CMake', short: 'cmake', extension: 'cmake', commentStart: '# ', commentEnd: '', mode: hl_cmake.cmake, otherExtensions: const []),
  Language.groovy: LanguageInfo(label: 'Groovy', short: 'groovy', extension: 'groovy', commentStart: '// ', commentEnd: '', mode: hl_groovy.groovy, otherExtensions: const []),
  Language.gradle: LanguageInfo(label: 'Gradle', short: 'gradle', extension: 'gradle', commentStart: '// ', commentEnd: '', mode: hl_gradle.gradle, otherExtensions: const []),
  Language.protobuf: LanguageInfo(label: 'Protocol Buffers', short: 'protobuf', extension: 'proto', commentStart: '// ', commentEnd: '', mode: hl_protobuf.protobuf, otherExtensions: const []),
  Language.graphql: LanguageInfo(label: 'GraphQL', short: 'graphql', extension: 'graphql', commentStart: '# ', commentEnd: '', mode: hl_graphql.graphql, otherExtensions: const ['gql']),
  Language.nginx: LanguageInfo(label: 'Nginx config', short: 'nginx', extension: 'conf', commentStart: '# ', commentEnd: '', mode: hl_nginx.nginx, otherExtensions: const []),
  Language.toml: LanguageInfo(label: 'TOML / INI', short: 'toml', extension: 'toml', commentStart: '# ', commentEnd: '', mode: hl_ini.ini, otherExtensions: const ['ini', 'cfg']),
  Language.julia: LanguageInfo(label: 'Julia', short: 'julia', extension: 'jl', commentStart: '# ', commentEnd: '', mode: hl_julia.julia, otherExtensions: const []),
  Language.fSharp: LanguageInfo(label: 'F#', short: 'f#', extension: 'fs', commentStart: '// ', commentEnd: '', mode: hl_fsharp.fsharp, otherExtensions: const ['fsx']),
  Language.vbNet: LanguageInfo(label: 'VB.NET', short: 'vb.net', extension: 'vb', commentStart: '\' ', commentEnd: '', mode: hl_vbnet.vbnet, otherExtensions: const []),
  Language.clojure: LanguageInfo(label: 'Clojure', short: 'clojure', extension: 'clj', commentStart: '; ', commentEnd: '', mode: hl_clojure.clojure, otherExtensions: const ['cljs', 'edn']),
  Language.erlang: LanguageInfo(label: 'Erlang', short: 'erlang', extension: 'erl', commentStart: '% ', commentEnd: '', mode: hl_erlang.erlang, otherExtensions: const ['hrl']),
  Language.scss: LanguageInfo(label: 'SCSS', short: 'scss', extension: 'scss', commentStart: '// ', commentEnd: '', mode: hl_scss.scss, otherExtensions: const ['sass']),
  Language.less: LanguageInfo(label: 'Less', short: 'less', extension: 'less', commentStart: '// ', commentEnd: '', mode: hl_less.less, otherExtensions: const []),
  Language.ocaml: LanguageInfo(label: 'OCaml', short: 'ocaml', extension: 'ml', commentStart: '(* ', commentEnd: ' *)', mode: hl_ocaml.ocaml, otherExtensions: const ['mli']),
  Language.fortran: LanguageInfo(label: 'Fortran', short: 'fortran', extension: 'f90', commentStart: '! ', commentEnd: '', mode: hl_fortran.fortran, otherExtensions: const ['f', 'f95']),
  Language.vhdl: LanguageInfo(label: 'VHDL', short: 'vhdl', extension: 'vhd', commentStart: '-- ', commentEnd: '', mode: hl_vhdl.vhdl, otherExtensions: const ['vhdl']),
  Language.verilog: LanguageInfo(label: 'Verilog', short: 'verilog', extension: 'v', commentStart: '// ', commentEnd: '', mode: hl_verilog.verilog, otherExtensions: const ['sv']),
  Language.solidity: LanguageInfo(label: 'Solidity', short: 'solidity', extension: 'sol', commentStart: '// ', commentEnd: '', mode: hl_solidity.solidity, otherExtensions: const []),
};

/// Info for [lang], falling back to plain text.
LanguageInfo languageInfo(Language lang) =>
    languages[lang] ?? languages[Language.none]!;

/// Languages in menu order: alphabetical, with plain text last.
List<Language> get menuLanguages {
  final list = languages.keys.where((l) => l != Language.none).toList()
    ..sort((a, b) => languages[a]!.label.toLowerCase()
        .compareTo(languages[b]!.label.toLowerCase()));
  return [...list, Language.none];
}

/// The language for a file name like `main.rs` or `Dockerfile`.
Language languageForFileName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower == 'dockerfile') return Language.docker;
  if (lower == 'makefile') return Language.makefile;
  if (lower == 'cmakelists.txt') return Language.cmake;
  final dot = fileName.lastIndexOf('.');
  if (dot < 0) return Language.none;
  final ext = fileName.substring(dot + 1);
  // Check exact case first (".R" is R), then lowercase.
  for (final entry in languages.entries) {
    final info = entry.value;
    if (entry.key == Language.django || entry.key == Language.pgSql) continue;
    if (info.extension == ext || info.otherExtensions.contains(ext)) {
      return entry.key;
    }
  }
  final low = ext.toLowerCase();
  for (final entry in languages.entries) {
    final info = entry.value;
    if (entry.key == Language.django || entry.key == Language.pgSql) continue;
    if (info.extension.toLowerCase() == low ||
        info.otherExtensions.any((e) => e.toLowerCase() == low)) {
      return entry.key;
    }
  }
  return Language.none;
}
