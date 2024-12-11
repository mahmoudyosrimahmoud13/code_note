import 'package:code_note/widgets/block/block.dart';
import 'package:code_note/widgets/custom_icon_button.dart';
import 'package:code_note/widgets/language_drop_down.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:highlight/highlight_core.dart' as highligt;

import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/arduino.dart';
import 'package:highlight/languages/armasm.dart';
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/cs.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/django.dart';
import 'package:highlight/languages/dockerfile.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/htmlbars.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/kotlin.dart';
import 'package:highlight/languages/php.dart';
import 'package:highlight/languages/pgsql.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/x86asm.dart';

class CodeBlock extends Block {
  CodeBlock({
    super.key,
    required super.id,
    this.language,
    super.moveUp,
    super.moveDown,
    super.delete,
    super.text,
  }) {
    super.text ??= '';
  }

  Language? language;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  final _controller = CodeController(
    text: '',
    // Initial code
    language: python,
  );
  void _addSyntax(String syntax) {
    setState(() {
      _controller.text = _controller.text + syntax;
    });
  }

  // highligt.Mode _controller.language  = python;
  void selectLanguageMode({required Language language}) {
    switch (language) {
      case Language.python:
        _langRow = Row(
          children: [Brand(Brands.python), const Text('Python')],
        );
        widget.language = Language.python;
        _controller.language = python;
        break;
      case Language.cSharp:
        _langRow = Row(
          children: [Brand(Brands.c_sharp_logo), const Text('C#')],
        );
        widget.language = Language.cSharp;
        _controller.language = cs;
        break;
      case Language.dart:
        _langRow = Row(
          children: [Brand(Brands.dart), const Text('Dart')],
        );
        widget.language = Language.dart;
        _controller.language = dart;
        break;
      case Language.go:
        _langRow = Row(
          children: [Brand(Brands.golang), const Text('Go')],
        );
        widget.language = Language.go;
        _controller.language = go;
        break;
      case Language.java:
        _langRow = Row(
          children: [Brand(Brands.java), const Text('Java')],
        );
        widget.language = Language.java;
        _controller.language = java;
        break;
      case Language.javaScript:
        _langRow = Row(
          children: [Brand(Brands.javascript), const Text('JavaScript')],
        );
        widget.language = Language.javaScript;
        _controller.language = javascript;
        break;
      case Language.typeScript:
        _langRow = Row(
          children: [Brand(Brands.typescript), const Text('TypeScript')],
        );
        widget.language = Language.typeScript;
        _controller.language = typescript;
        break;
      case Language.cpp:
        _langRow = Row(
          children: [Brand(Brands.cpp), const Text('C++')],
        );
        widget.language = Language.cpp;
        _controller.language = cpp;
        break;
      case Language.php:
        _langRow = Row(
          children: [Brand(Brands.php_designer), const Text('PHP')],
        );
        widget.language = Language.php;
        _controller.language = php;
        break;
      case Language.arduino:
        _langRow = Row(
          children: [Brand(Brands.arduino), const Text('Arduino')],
        );
        widget.language = Language.arduino;
        _controller.language = arduino;
        break;
      case Language.armAssembly:
        _langRow = Row(
          children: [Brand(Brands.arm_logo), const Text('ARM Assembly')],
        );
        widget.language = Language.armAssembly;
        _controller.language = armasm;
        break;
      case Language.x86Assembly:
        _langRow = Row(
          children: [Brand(Brands.amd), const Text('x86 Assembly')],
        );
        widget.language = Language.x86Assembly;
        _controller.language = x86Asm;
        break;
      case Language.bash:
        _langRow = Row(
          children: [Brand(Brands.bash), const Text('Bash')],
        );
        widget.language = Language.bash;
        _controller.language = bash;
        break;
      case Language.django:
        _langRow = Row(
          children: [Brand(Brands.django), const Text('Django')],
        );
        widget.language = Language.django;
        _controller.language = django;
        break;
      case Language.html:
        _langRow = Row(
          children: [Brand(Brands.html_5), const Text('HTML')],
        );
        widget.language = Language.html;
        _controller.language = htmlbars;
        break;
      case Language.css:
        _langRow = Row(
          children: [Brand(Brands.css3), const Text('CSS')],
        );
        widget.language = Language.css;
        _controller.language = css;
        break;
      case Language.docker:
        _langRow = Row(
          children: [Brand(Brands.docker), const Text('Docker')],
        );
        widget.language = Language.docker;
        _controller.language = dockerfile;
        break;
      case Language.kotlin:
        _langRow = Row(
          children: [Brand(Brands.kotlin), const Text('Kotlin')],
        );
        widget.language = Language.kotlin;
        _controller.language = kotlin;
        break;
      case Language.sql:
        _langRow = Row(
          children: [Brand(Brands.my_sql), const Text('SQL')],
        );
        widget.language = Language.sql;
        _controller.language = sql;
        break;
      case Language.pgSql:
        _langRow = Row(
          children: [Brand(Brands.postgresql), const Text('PostgreSQL')],
        );
        widget.language = Language.pgSql;
        _controller.language = pgsql;
        break;
      case Language.json:
        _langRow = Row(
          children: [Brand(Brands.json_web_token), const Text('JSON')],
        );
        widget.language = Language.json;
        _controller.language = json;
        break;
      default:
        _langRow = Row(
          children: [Brand(Brands.python), const Text('Python')],
        );
        widget.language = Language.python;
        _controller.language = python;
    }
  }

  @override
  void initState() {
    // TODO: implement initState

    _controller.text = widget.text!;
    selectLanguageMode(language: widget.language!);
    _controller.language = _controller.language;

    super.initState();
  }

  @override
  void dispose() {
    // TODO: implement dispose
    widget.text = _controller.text;
    super.dispose();
  }

  Widget _langRow = Row(
    children: [Brand(Brands.python), const Text('Python')],
  );

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
          color: color.secondary.withAlpha(50),
          borderRadius: BorderRadius.circular(30)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                LanguageDropDown(
                  language: widget.language!,
                  selectLanguage: (languages) {
                    setState(() {
                      selectLanguageMode(language: languages!);
                    });

                    _controller.language = _controller.language;
                  },
                ),
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  width: 208,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CustomIconButton(
                        icon: Icons.delete,
                        iconSize: 18,
                        innerColor: color.onError,
                        iconColor: color.error,
                        onPressed: () {
                          widget.delete!(widget.id);
                        },
                      ),
                      CustomIconButton(
                        icon: Icons.arrow_upward,
                        iconSize: 18,
                        onPressed: () {
                          widget.moveUp!(widget.id);
                        },
                      ),
                      CustomIconButton(
                        icon: Icons.arrow_downward,
                        iconSize: 18,
                        onPressed: () {
                          widget.moveDown!(widget.id);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          CodeTheme(
            data: CodeThemeData(styles: monokaiSublimeTheme),
            child: CodeField(
              background: Colors.transparent,
              controller: _controller,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CustomIconButton(
                  text: ';',
                  iconSize: 8,
                  innerColor: Colors.transparent,
                  onPressed: () => _addSyntax(';'),
                ),
                CustomIconButton(
                  text: "'",
                  iconSize: 8,
                  innerColor: Colors.transparent,
                  onPressed: () => _addSyntax("'"),
                ),
                CustomIconButton(
                  text: "{}",
                  iconSize: 8,
                  innerColor: Colors.transparent,
                  onPressed: () => _addSyntax("{}"),
                ),
                CustomIconButton(
                  text: '(',
                  iconSize: 8,
                  innerColor: Colors.transparent,
                  onPressed: () => _addSyntax('('),
                ),
                CustomIconButton(
                  text: ')',
                  iconSize: 8,
                  innerColor: Colors.transparent,
                  onPressed: () => _addSyntax(')'),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

enum Language {
  none,
  python,
  cSharp,
  dart,
  go,
  java,
  javaScript,
  typeScript,
  cpp,
  php,
  arduino,
  armAssembly,
  x86Assembly,
  bash,
  django,
  html,
  css,
  docker,
  kotlin,
  sql,
  pgSql,
  json
}
