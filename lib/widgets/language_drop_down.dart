import 'package:flutter/material.dart';
import 'package:icons_plus/icons_plus.dart';
import '../features/notes/domain/entities/language.dart';

class LanguageDropDown extends StatefulWidget {
  const LanguageDropDown({
    super.key,
    required this.selectLanguage,
    required this.language,
  });

  final void Function(Language? languages)? selectLanguage;
  final Language language;

  @override
  State<LanguageDropDown> createState() => _LanguageDropDownState();
}

class _LanguageDropDownState extends State<LanguageDropDown> {
  List<DropdownMenuItem<Language>> get _items => [
    _buildItem(Language.python, Brands.python, 'Python'),
    _buildItem(Language.cSharp, Brands.c_sharp_logo, 'C#'),
    _buildItem(Language.dart, Brands.dart, 'Dart'),
    _buildItem(Language.go, Brands.golang, 'Go'),
    _buildItem(Language.java, Brands.java, 'Java'),
    _buildItem(Language.javaScript, Brands.javascript, 'JavaScript', fontSize: 12),
    _buildItem(Language.typeScript, Brands.typescript, 'TypeScript', fontSize: 12),
    _buildItem(Language.cpp, Brands.cpp, 'C++'),
    _buildItem(Language.php, null, 'PHP', icon: BoxIcons.bxl_php),
    _buildItem(Language.arduino, Brands.arduino, 'Arduino'),
    _buildItem(Language.armAssembly, Brands.arm_logo, 'ARM Assembly', fontSize: 10),
    _buildItem(Language.x86Assembly, Brands.amd, 'x86 Assembly', fontSize: 10),
    _buildItem(Language.bash, Brands.bash, 'Bash'),
    _buildItem(Language.django, Brands.django, 'Django'),
    _buildItem(Language.html, Brands.html_5, 'HTML'),
    _buildItem(Language.css, Brands.css3, 'CSS'),
    _buildItem(Language.docker, Brands.docker, 'Docker'),
    _buildItem(Language.kotlin, Brands.kotlin, 'Kotlin'),
    _buildItem(Language.sql, Brands.my_sql, 'SQL'),
    _buildItem(Language.pgSql, Brands.postgresql, 'PostgreSQL'),
    _buildItem(Language.json, null, 'JSON', icon: BoxIcons.bx_code),
  ];

  DropdownMenuItem<Language> _buildItem(Language value, String? brand, String label, {double? fontSize, IconData? icon}) {
    return DropdownMenuItem(
      value: value,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (brand != null) SizedBox(width: 24, height: 24, child: Brand(brand)) else if (icon != null) Icon(icon, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: fontSize != null ? TextStyle(fontSize: fontSize) : null,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
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
