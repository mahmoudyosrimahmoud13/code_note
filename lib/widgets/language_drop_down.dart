import 'package:flutter/material.dart';

import '../constants/themes.dart';
import '../core/util/code_languages.dart';
import '../features/notes/domain/entities/language.dart';

/// The language button on a code block. Tapping it opens a searchable list
/// of every supported language.
class LanguageDropDown extends StatelessWidget {
  const LanguageDropDown({
    super.key,
    required this.selectLanguage,
    required this.language,
  });

  final void Function(Language? language)? selectLanguage;
  final Language language;

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<Language>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LanguagePickerSheet(current: language),
    );
    if (picked != null) selectLanguage?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Change language',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: context.tokens.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                languageInfo(language).label,
                style: monoStyle(context, size: 13, weight: FontWeight.w500),
              ),
              Icon(Icons.expand_more_rounded, size: 18, color: color.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguagePickerSheet extends StatefulWidget {
  const _LanguagePickerSheet({required this.current});
  final Language current;

  @override
  State<_LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<_LanguagePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final list = menuLanguages.where((l) {
      if (q.isEmpty) return true;
      final info = languageInfo(l);
      return info.label.toLowerCase().contains(q) ||
          info.short.contains(q) ||
          info.extension.toLowerCase() == q.replaceAll('.', '') ||
          info.otherExtensions.contains(q.replaceAll('.', ''));
    }).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: true,
                  style: monoStyle(context, size: 14),
                  decoration: InputDecoration(
                    hintText: 'Search languages or .ext',
                    hintStyle: monoStyle(context, size: 14, color: context.tokens.subtle),
                    prefixIcon: Icon(Icons.search_rounded, color: color.primary),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Text('no match',
                            style: monoStyle(context, color: context.tokens.subtle)),
                      )
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final lang = list[i];
                          final info = languageInfo(lang);
                          final selected = lang == widget.current;
                          return ListTile(
                            dense: true,
                            selected: selected,
                            leading: Icon(
                              selected ? Icons.check_rounded : Icons.code_rounded,
                              size: 18,
                            ),
                            title: Text(info.label),
                            trailing: Text('.${info.extension}',
                                style: monoStyle(context,
                                    size: 12, color: context.tokens.subtle)),
                            onTap: () => Navigator.pop(context, lang),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
