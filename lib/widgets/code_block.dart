import 'package:code_note/widgets/block.dart';
import 'package:code_note/widgets/custom_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/python.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:icons_plus/icons_plus.dart';

class CodeBlock extends Block {
  CodeBlock({super.key, required super.id, super.onPressed});

  final te = '';

  @override
  Widget build(BuildContext context) {
    final controller = CodeController(
      text: te,
      // Initial code
      language: python,
    );
    final size = MediaQuery.of(context).size;
    final text = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    return Container(
      margin: EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
          color: color.secondary.withAlpha(50),
          borderRadius: BorderRadius.circular(30)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [Brand(Brands.python), Text('python')],
                ),
                Row(
                  children: [
                    CustomIconButton(
                      icon: Icons.edit,
                      iconSize: 15,
                    ),
                    CustomIconButton(
                      icon: Icons.delete,
                      iconSize: 15,
                      innerColor: color.onError,
                      iconColor: color.error,
                      onPressed: () {
                        onPressed!(id);
                      },
                    )
                  ],
                )
              ],
            ),
          ),
          CodeTheme(
            data: CodeThemeData(styles: monokaiSublimeTheme),
            child: CodeField(
              background: Colors.transparent,
              controller: controller,
            ),
          ),
        ],
      ),
    );
  }
}
