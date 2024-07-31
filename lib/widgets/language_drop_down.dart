import 'package:code_note/widgets/block/code_block.dart';
import 'package:flutter/material.dart';
import 'package:icons_plus/icons_plus.dart';

class LanguageDropDown extends StatefulWidget {
  LanguageDropDown(
      {super.key, required this.selectLanguage, required this.language});
  final void Function(Language? languages)? selectLanguage;
  Language language;

  @override
  State<LanguageDropDown> createState() => _LanguageDropDownState();
}

class _LanguageDropDownState extends State<LanguageDropDown> {
  final List<DropdownMenuItem<Language>> _items = [
    DropdownMenuItem(
      value: Language.python,
      child: Row(
        children: [
          Brand(Brands.python),
          const SizedBox(width: 10),
          const Text('Python'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.cSharp,
      child: Row(
        children: [
          Brand(Brands.c_sharp_logo),
          const SizedBox(width: 10),
          const Text('C#'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.dart,
      child: Row(
        children: [
          Brand(Brands.dart),
          const SizedBox(width: 10),
          const Text('Dart'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.go,
      child: Row(
        children: [
          Brand(Brands.golang),
          const SizedBox(width: 10),
          const Text('Go'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.java,
      child: Row(
        children: [
          Brand(
            Brands.java,
          ),
          const Text('Java'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.javaScript,
      child: Row(
        children: [
          Brand(Brands.javascript),
          const SizedBox(width: 10),
          const Text(
            'JavaScript',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.typeScript,
      child: Row(
        children: [
          Brand(Brands.typescript),
          const SizedBox(width: 10),
          const Text(
            'TypeScript',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.cpp,
      child: Row(
        children: [
          Brand(Brands.cpp),
          const SizedBox(width: 10),
          const Text('C++'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.php,
      child: Row(
        children: [
          Icon(
            BoxIcons.bxl_php,
            size: 40,
          ),
          const SizedBox(width: 10),
          const Text('PHP'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.arduino,
      child: Row(
        children: [
          Brand(Brands.arduino),
          const SizedBox(width: 10),
          const Text('Arduino'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.armAssembly,
      child: Row(
        children: [
          Brand(Brands.arm_logo),
          const SizedBox(width: 10),
          const Text(
            'ARM Assembly',
            style: TextStyle(fontSize: 10),
          ),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.x86Assembly,
      child: Row(
        children: [
          Brand(Brands.amd),
          const SizedBox(width: 10),
          const Text(
            'x86 Assembly',
            style: TextStyle(fontSize: 10),
          ),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.bash,
      child: Row(
        children: [
          Brand(Brands.bash),
          const SizedBox(width: 10),
          const Text('Bash'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.django,
      child: Row(
        children: [
          Brand(Brands.django),
          const SizedBox(width: 10),
          const Text('Django'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.html,
      child: Row(
        children: [
          Brand(Brands.html_5),
          const SizedBox(width: 10),
          const Text('HTML'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.css,
      child: Row(
        children: [
          Brand(Brands.css3),
          const SizedBox(width: 10),
          const Text('CSS'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.docker,
      child: Row(
        children: [
          Brand(Brands.docker),
          const SizedBox(width: 10),
          const Text('Docker'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.kotlin,
      child: Row(
        children: [
          Brand(Brands.kotlin),
          const SizedBox(width: 10),
          const Text('Kotlin'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.sql,
      child: Row(
        children: [
          Brand(Brands.my_sql),
          const SizedBox(width: 10),
          const Text('SQL'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.pgSql,
      child: Row(
        children: [
          Brand(Brands.postgresql),
          const SizedBox(width: 10),
          const Text('PostgreSQL'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: Language.json,
      child: Row(
        children: [
          Icon(BoxIcons.bx_code),
          const SizedBox(width: 10),
          const Text('JSON'),
        ],
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return SizedBox(
      width: 140,
      child: DropdownButton(
        isExpanded: true,
        dropdownColor: color.primary.withAlpha(70),
        borderRadius: BorderRadius.circular(30),
        underline: const SizedBox.shrink(),
        items: _items,
        value: widget.language,
        onChanged: (value) {
          setState(() {
            widget.selectLanguage!(value);
          });
        },
      ),
    );
  }
}
