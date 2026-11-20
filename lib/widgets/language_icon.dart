import 'package:flutter/material.dart';

import '../features/notes/domain/entities/language.dart';

/// The language's logo (from Devicon, MIT license), or a code icon for
/// languages without one.
class LanguageIcon extends StatelessWidget {
  const LanguageIcon(this.language, {super.key, this.size = 18});

  final Language language;
  final double size;

  static const _withLogo = <Language>{
    Language.arduino,
    Language.armAssembly,
    Language.bash,
    Language.c,
    Language.cSharp,
    Language.clojure,
    Language.cmake,
    Language.cpp,
    Language.css,
    Language.dart,
    Language.django,
    Language.docker,
    Language.elixir,
    Language.erlang,
    Language.fSharp,
    Language.fortran,
    Language.go,
    Language.gradle,
    Language.graphql,
    Language.groovy,
    Language.haskell,
    Language.html,
    Language.java,
    Language.javaScript,
    Language.json,
    Language.julia,
    Language.kotlin,
    Language.less,
    Language.lua,
    Language.markdown,
    Language.matlab,
    Language.nginx,
    Language.objectiveC,
    Language.ocaml,
    Language.perl,
    Language.pgSql,
    Language.php,
    Language.powershell,
    Language.protobuf,
    Language.python,
    Language.r,
    Language.ruby,
    Language.rust,
    Language.scala,
    Language.scss,
    Language.solidity,
    Language.sql,
    Language.swift,
    Language.toml,
    Language.typeScript,
    Language.vbNet,
    Language.verilog,
    Language.x86Assembly,
    Language.xml,
    Language.yaml,
  };

  /// Black-only logos: drawn in the text color so they show on dark themes.
  static const _monochrome = <Language>{
    Language.rust,
    Language.markdown,
    Language.yaml,
    Language.solidity,
    Language.django,
  };

  static bool hasLogo(Language language) => _withLogo.contains(language);

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(Icons.code_rounded, size: size,
        color: Theme.of(context).colorScheme.onSurfaceVariant);
    if (!_withLogo.contains(language)) return fallback;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      'assets/languages/${language.name}.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      color: dark && _monochrome.contains(language)
          ? Theme.of(context).colorScheme.onSurface
          : null,
      colorBlendMode: BlendMode.srcIn,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
