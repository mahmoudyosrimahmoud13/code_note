import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_saver/file_saver.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import '../../helpers/helper_methods.dart';
import '../../features/notes/domain/entities/block.dart';
import '../../features/notes/domain/entities/language.dart';
import '../../features/notes/domain/entities/note.dart';
import 'code_languages.dart';
import 'platform_helper.dart';

class NoteShareHelper {
  static String formatNoteAsText(NoteEntity note, {Language? targetLanguage}) {
    final buffer = StringBuffer();
    final langInfo = languageInfo(targetLanguage ?? Language.none);
    
    buffer.writeln('${langInfo.commentStart}Title: ${note.title}${langInfo.commentEnd}');
    buffer.writeln('${langInfo.commentStart}Last Modified: ${note.lastModified}${langInfo.commentEnd}');
    buffer.writeln();

    for (var block in note.blocks) {
      if (block is NoteBlockEntity) {
        if (block.text != null && block.text!.isNotEmpty) {
          final lines = block.text!.split('\n');
          for (var line in lines) {
            buffer.writeln('${langInfo.commentStart}$line${langInfo.commentEnd}');
          }
          buffer.writeln();
        }
      } else if (block is CodeBlockEntity) {
        if (block.text != null && block.text!.isNotEmpty) {
          buffer.writeln(block.text);
          buffer.writeln();
        }
      }
    }
    return buffer.toString();
  }

  static String formatBlockAsText(BlockEntity block) {
    if (block is CodeBlockEntity) {
      return block.text ?? '';
    } else if (block is NoteBlockEntity) {
      return block.text ?? '';
    }
    return '';
  }

  static Future<void> shareNoteAsFile(NoteEntity note, Language language) async {
    final content = formatNoteAsText(note, targetLanguage: language);
    final langInfo = languageInfo(language);
    final baseName = note.title.isEmpty ? 'note' : note.title.replaceAll(RegExp(r'[^\w\s]+'), '_');
    final fileName = '$baseName.${langInfo.extension}';
    
    if (PlatformHelper.isDesktopOrWeb) {
      await _saveAsFile(content, baseName, langInfo.extension);
    } else {
      await _shareViaNative(content, fileName, note.title);
    }
  }

  static Future<void> shareBlockAsFile(BlockEntity block, String title, Language language) async {
    final content = formatBlockAsText(block);
    final langInfo = languageInfo(language);
    const baseName = 'code_block';
    final fileName = '$baseName.${langInfo.extension}';
    
    if (PlatformHelper.isDesktopOrWeb) {
      await _saveAsFile(content, baseName, langInfo.extension);
    } else {
      await _shareViaNative(content, fileName, title);
    }
  }

  static Future<void> shareAsTxt(NoteEntity note) async {
    final content = formatNoteAsText(note, targetLanguage: Language.none);
    final baseName = note.title.isEmpty ? 'note' : note.title.replaceAll(RegExp(r'[^\w\s]+'), '_');
    final fileName = '$baseName.txt';
    
    if (PlatformHelper.isDesktopOrWeb) {
      await _saveAsFile(content, baseName, 'txt');
    } else {
      await _shareViaNative(content, fileName, note.title);
    }
  }

  static Future<void> _saveAsFile(String content, String name, String ext) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    
    if (PlatformHelper.isDesktopOrWeb) {
      final fileName = '$name.$ext';
      final result = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          XTypeGroup(
            label: ext.toUpperCase(),
            extensions: [ext],
          ),
        ],
      );

      if (result != null) {
        final file = XFile.fromData(bytes, name: fileName, mimeType: 'text/plain');
        await file.saveTo(result.path);
        if (kIsWeb) {
          showMessage(message: 'File download started: $fileName');
        } else {
          showMessage(message: 'Saved to: ${result.path}');
        }
      }
    } else {
      // For Mobile, file_saver or share_plus is better
      await FileSaver.instance.saveFile(
        name: '$name.$ext',
        bytes: bytes,
        mimeType: MimeType.text,
      );
    }
  }

  static Future<void> _shareViaNative(String content, String fileName, String title) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsString(content, flush: true);

    // Using Share.shareXFiles is standard for files in share_plus
    await Share.shareXFiles(
      [XFile(file.path, name: fileName)],
      text: 'Sharing Note: $title',
      subject: 'CodeNote: $title',
    );
  }

  static void copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
  }
}
