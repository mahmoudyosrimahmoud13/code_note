import 'package:code_note/widgets/block.dart';
import 'package:code_note/widgets/custom_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/python.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:icons_plus/icons_plus.dart';

class CodeBlock extends Block {
  CodeBlock({
    super.key,
    required super.id,
    super.moveUp,
    super.moveDown,
    super.onPressed,
    this.code,
  }) {
    code ??= '';
  }

  String? code;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  final controller = CodeController(
    text: '',
    // Initial code
    language: python,
  );
  void _addSyntax(String syntax) {
    setState(() {
      controller.text = controller.text + syntax;
    });
  }

  @override
  void initState() {
    // TODO: implement initState
    controller.text = widget.code!;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
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
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 3, vertical: 5),
                  padding: EdgeInsets.symmetric(vertical: 4),
                  width: 220,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CustomIconButton(
                        icon: Icons.delete,
                        iconSize: 15,
                        innerColor: color.onError,
                        iconColor: color.error,
                        onPressed: () {
                          widget.onPressed!(widget.id);
                        },
                      ),
                      CustomIconButton(
                        icon: Icons.arrow_upward,
                        iconSize: 15,
                        onPressed: () {
                          widget.moveUp!(widget.id);
                        },
                      ),
                      CustomIconButton(
                        icon: Icons.arrow_downward,
                        iconSize: 15,
                        onPressed: () {
                          widget.moveDown!(widget.id);
                        },
                      )
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
              controller: controller,
            ),
          ),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 3, vertical: 5),
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CustomIconButton(
                  text: ';',
                  iconSize: 15,
                  innerColor: Colors.transparent,
                  onPressed: () => _addSyntax(';'),
                ),
                CustomIconButton(
                  text: '(',
                  iconSize: 15,
                  innerColor: Colors.transparent,
                  onPressed: () => _addSyntax('('),
                ),
                CustomIconButton(
                  text: ')',
                  iconSize: 15,
                  innerColor: Colors.transparent,
                  onPressed: () => _addSyntax(')'),
                ),
                CustomIconButton(
                  text: "'",
                  iconSize: 15,
                  innerColor: Colors.transparent,
                  onPressed: () => _addSyntax("'"),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
