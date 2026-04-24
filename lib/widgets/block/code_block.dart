import 'package:code_note/widgets/block/block.dart';
import 'package:code_note/widgets/custom_icon_button.dart';
import 'package:code_note/widgets/language_drop_down.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:highlight/highlight_core.dart' as highlight;

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
import '../../features/notes/domain/entities/block.dart';
import '../../features/notes/domain/entities/language.dart';

class CodeBlock extends Block {
  const CodeBlock({
    super.key,
    required super.entity,
    super.moveUp,
    super.moveDown,
    super.delete,
    super.onChanged,
  });

  CodeBlockEntity get codeEntity => entity as CodeBlockEntity;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  late final CodeController _controller;
  Widget _langRow = Row(
    children: [Brand(Brands.python), const Text('Python')],
  );

  @override
  void initState() {
    super.initState();
    _controller = CodeController(
      text: widget.text ?? '',
      language: _getHighlightMode(widget.codeEntity.language),
    );
    _updateLangRow(widget.codeEntity.language);
  }

  highlight.Mode _getHighlightMode(Language lang) {
    switch (lang) {
      case Language.python: return python;
      case Language.cSharp: return cs;
      case Language.dart: return dart;
      case Language.go: return go;
      case Language.java: return java;
      case Language.javaScript: return javascript;
      case Language.typeScript: return typescript;
      case Language.cpp: return cpp;
      case Language.php: return php;
      case Language.arduino: return arduino;
      case Language.armAssembly: return armasm;
      case Language.x86Assembly: return x86Asm;
      case Language.bash: return bash;
      case Language.django: return django;
      case Language.html: return htmlbars;
      case Language.css: return css;
      case Language.docker: return dockerfile;
      case Language.kotlin: return kotlin;
      case Language.sql: return sql;
      case Language.pgSql: return pgsql;
      case Language.json: return json;
      default: return python;
    }
  }

  void _updateLangRow(Language language) {
    switch (language) {
      case Language.python:
        _langRow = Row(children: [Brand(Brands.python), const Text('Python')]);
        break;
      case Language.cSharp:
        _langRow = Row(children: [Brand(Brands.c_sharp_logo), const Text('C#')]);
        break;
      case Language.dart:
        _langRow = Row(children: [Brand(Brands.dart), const Text('Dart')]);
        break;
      case Language.go:
        _langRow = Row(children: [Brand(Brands.golang), const Text('Go')]);
        break;
      case Language.java:
        _langRow = Row(children: [Brand(Brands.java), const Text('Java')]);
        break;
      case Language.javaScript:
        _langRow = Row(children: [Brand(Brands.javascript), const Text('JavaScript')]);
        break;
      case Language.typeScript:
        _langRow = Row(children: [Brand(Brands.typescript), const Text('TypeScript')]);
        break;
      case Language.cpp:
        _langRow = Row(children: [Brand(Brands.cpp), const Text('C++')]);
        break;
      case Language.php:
        _langRow = Row(children: [Brand(Brands.php_designer), const Text('PHP')]);
        break;
      case Language.arduino:
        _langRow = Row(children: [Brand(Brands.arduino), const Text('Arduino')]);
        break;
      case Language.armAssembly:
        _langRow = Row(children: [Brand(Brands.arm_logo), const Text('ARM Assembly')]);
        break;
      case Language.x86Assembly:
        _langRow = Row(children: [Brand(Brands.amd), const Text('x86 Assembly')]);
        break;
      case Language.bash:
        _langRow = Row(children: [Brand(Brands.bash), const Text('Bash')]);
        break;
      case Language.django:
        _langRow = Row(children: [Brand(Brands.django), const Text('Django')]);
        break;
      case Language.html:
        _langRow = Row(children: [Brand(Brands.html_5), const Text('HTML')]);
        break;
      case Language.css:
        _langRow = Row(children: [Brand(Brands.css3), const Text('CSS')]);
        break;
      case Language.docker:
        _langRow = Row(children: [Brand(Brands.docker), const Text('Docker')]);
        break;
      case Language.kotlin:
        _langRow = Row(children: [Brand(Brands.kotlin), const Text('Kotlin')]);
        break;
      case Language.sql:
        _langRow = Row(children: [Brand(Brands.my_sql), const Text('SQL')]);
        break;
      case Language.pgSql:
        _langRow = Row(children: [Brand(Brands.postgresql), const Text('PostgreSQL')]);
        break;
      case Language.json:
        _langRow = Row(children: [Brand(Brands.json_web_token), const Text('JSON')]);
        break;
      default:
        _langRow = Row(children: [Brand(Brands.python), const Text('Python')]);
    }
  }

  void _addSyntax(String syntax) {
    _controller.text = _controller.text + syntax;
    if (widget.onChanged != null) {
      widget.onChanged!(widget.codeEntity.copyWith(text: _controller.text));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
                  language: widget.codeEntity.language, 
                  selectLanguage: (lang) {
                    if (lang != null) {
                      setState(() {
                        _controller.language = _getHighlightMode(lang);
                        _updateLangRow(lang);
                      });
                      if (widget.onChanged != null) {
                        widget.onChanged!(widget.codeEntity.copyWith(language: lang));
                      }
                    }
                  },
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
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
                        onPressed: () => widget.delete!(widget.id),
                      ),
                      CustomIconButton(
                        icon: Icons.arrow_upward,
                        iconSize: 18,
                        onPressed: () => widget.moveUp!(widget.id),
                      ),
                      CustomIconButton(
                        icon: Icons.arrow_downward,
                        iconSize: 18,
                        onPressed: () => widget.moveDown!(widget.id),
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
              onChanged: (val) {
                if (widget.onChanged != null) {
                  widget.onChanged!(widget.codeEntity.copyWith(text: val));
                }
              },
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CustomIconButton(text: ';', iconSize: 8, innerColor: Colors.transparent, onPressed: () => _addSyntax(';')),
                CustomIconButton(text: "'", iconSize: 8, innerColor: Colors.transparent, onPressed: () => _addSyntax("'")),
                CustomIconButton(text: "{}", iconSize: 8, innerColor: Colors.transparent, onPressed: () => _addSyntax("{}")),
                CustomIconButton(text: '(', iconSize: 8, innerColor: Colors.transparent, onPressed: () => _addSyntax('(')),
                CustomIconButton(text: ')', iconSize: 8, innerColor: Colors.transparent, onPressed: () => _addSyntax(')')),
              ],
            ),
          )
        ],
      ),
    );
  }
}
