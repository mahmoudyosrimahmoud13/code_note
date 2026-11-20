import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_info.dart';
import '../../constants/themes.dart';
import 'update_service.dart';

/// Shows "CodeNote x.y.z is available" with the release notes.
Future<void> showUpdateDialog(BuildContext context, AppUpdate update) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('CodeNote ${update.version} is available'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You have v$appVersion.',
                style: monoStyle(dialogContext,
                    size: 12, color: dialogContext.tokens.subtle)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: MarkdownBody(
                  data: update.notes.trim().isEmpty
                      ? 'See the release page for what changed.'
                      : update.notes,
                  onTapLink: (_, href, __) {
                    if (href != null) {
                      launchUrl(Uri.parse(href),
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            UpdateService.instance.skip(update.version);
            Navigator.pop(dialogContext);
          },
          child: const Text('Skip this version'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Later'),
        ),
        FilledButton.icon(
          onPressed: () {
            launchUrl(Uri.parse(update.downloadUrl ?? update.pageUrl),
                mode: LaunchMode.externalApplication);
            Navigator.pop(dialogContext);
          },
          icon: const Icon(Icons.download_rounded),
          label: const Text('Download'),
        ),
      ],
    ),
  );
}
