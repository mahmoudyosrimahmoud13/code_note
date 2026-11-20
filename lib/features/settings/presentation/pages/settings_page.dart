import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../constants/app_info.dart';
import '../../../ai/ai_settings_page.dart';
import '../../../../constants/themes.dart';

import '../../../../core/util/image_helper.dart';
import '../../../../widgets/user_avatar.dart';
import '../../domain/entities/settings.dart';
import '../bloc/settings_bloc.dart';
import '../bloc/settings_event.dart';
import '../bloc/settings_state.dart';
import 'profile_edit_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Settings page state

  Future<void> _pickImage(SettingsEntity settings) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (image != null && mounted) {
      final settingsBloc = context.read<SettingsBloc>();
      final persistentPath = await ImageHelper.persistImage(image.path);
      if (!mounted) return;
      settingsBloc.add(UpdateSettingsEvent(
        settings.copyWith(profileImagePath: persistentPath),
      ));
    }
  }


  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          if (state is SettingsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is SettingsLoaded) {
            final settings = state.settings;

            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.surface,
                    color.primaryContainer.withAlpha(30)
                  ],
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 120, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProfileCard(settings, color, textTheme),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Appearance', textTheme, color),
                    const SizedBox(height: 16),
                    _buildSettingTile(
                      'Theme',
                      'Light, dark, or follow your device',
                      Icons.contrast_rounded,
                      color.primary,
                      bottom: SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'light',
                                icon: Icon(Icons.light_mode_outlined),
                                label: Text('Light')),
                            ButtonSegment(
                                value: 'dark',
                                icon: Icon(Icons.dark_mode_outlined),
                                label: Text('Dark')),
                            ButtonSegment(
                                value: 'system',
                                icon: Icon(Icons.brightness_auto_outlined),
                                label: Text('System')),
                          ],
                          selected: {settings.themeMode},
                          showSelectedIcon: false,
                          onSelectionChanged: (v) => context
                              .read<SettingsBloc>()
                              .add(UpdateSettingsEvent(
                                  settings.copyWith(themeMode: v.first))),
                        ),
                      ),
                      color: color,
                    ),
                    const SizedBox(height: 16),
                    _buildSettingTile(
                      'Text size',
                      '${(settings.fontSizeMultiplier * 100).round()}%',
                      Icons.format_size_rounded,
                      color.primary,
                      bottom: Column(children: [
                        Text(
                          'The quick brown fox writes clean code.',
                          style: textTheme.bodyLarge,
                        ),
                        Slider(
                        value: settings.fontSizeMultiplier,
                        min: 0.8,
                        max: 1.5,
                        divisions: 7,
                        onChanged: (v) => context.read<SettingsBloc>().add(
                            UpdateSettingsEvent(
                                settings.copyWith(fontSizeMultiplier: v))),
                      ),
                      ]),
                      color: color,
                    ),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Management', textTheme, color),
                    const SizedBox(height: 16),
                    _buildSettingTile(
                        'Clear All Data',
                        'Delete all local notes and settings',
                        Icons.delete_forever_rounded,
                        color.error,
                        onTap: () => _showClearDataConfirmation(context),
                        color: color),
                    const SizedBox(height: 32),
                    _buildSectionHeader('AI assistant', textTheme, color),
                    const SizedBox(height: 16),
                    _buildSettingTile(
                      'AI assistant',
                      'Explain code, find bugs. Claude, OpenAI-compatible or Ollama (offline)',
                      Icons.auto_awesome_outlined,
                      color.primary,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AiSettingsPage()),
                      ),
                      color: color,
                    ),
                    const SizedBox(height: 32),
                    _buildSectionHeader('About', textTheme, color),
                    const SizedBox(height: 16),
                    _buildSettingTile(
                      'GitHub Project',
                      'View source and contribute',
                      Icons.code_rounded,
                      color.primary,
                      onTap: () => launchUrl(Uri.parse(
                          'https://github.com/mahmoudyosrimahmoud13/code_note')),
                      color: color,
                    ),
                    const SizedBox(height: 16),
                    _buildSettingTile(
                      'Version',
                      'v$appVersion · Community Edition (local-only)',
                      Icons.info_outline_rounded,
                      color.primary,
                      color: color,
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            );
          }
          return const Center(child: Text('Something went wrong'));
        },
      ),
    );
  }

  Widget _buildProfileCard(SettingsEntity settings, ColorScheme color, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppBrand.radius),
        border: Border.all(color: color.outlineVariant.withAlpha(50)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                children: [
                  Hero(
                    tag: 'user_profile_photo',
                    child: UserAvatar(
                        imageUrl: settings.profileImagePath,
                        seed: settings.userHandle,
                        radius: 50),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () => _pickImage(settings),
                      child: Tooltip(
                        message: 'Change photo',
                        child: CircleAvatar(
                            backgroundColor: color.primary,
                            radius: 16,
                            child: Icon(Icons.camera_alt,
                                size: 14, color: color.onPrimary)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(settings.userName,
                        style: textTheme.headlineSmall!
                            .copyWith(fontWeight: FontWeight.bold)),
                    Text('@${settings.userHandle}',
                        style: textTheme.bodyLarge!
                            .copyWith(color: color.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ProfileEditPage(settings: settings)),
            ),
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('Edit Profile'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 45),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, TextTheme textTheme, ColorScheme color) {
    return Semantics(
      header: true,
      child: Text('// ${title.toLowerCase()}',
          style: monoStyle(context,
              size: 13, weight: FontWeight.w700, color: color.primary)),
    );
  }

  Widget _buildSettingTile(String title, String subtitle, IconData icon, Color iconColor,
      {Widget? trailing, Widget? bottom, VoidCallback? onTap, required ColorScheme color}) {
    return Container(
      decoration: BoxDecoration(
        color: color.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppBrand.radius),
        border: Border.all(color: color.outlineVariant.withAlpha(160)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppBrand.radius),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: iconColor.withAlpha(28),
                        borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
                      ),
                      child: Icon(icon, color: iconColor, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(subtitle, style: TextStyle(color: color.onSurfaceVariant, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (trailing != null) trailing,
                  ],
                ),
                if (bottom != null) ...[
                  const SizedBox(height: 12),
                  bottom,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showClearDataConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data?'),
        content: const Text('This will delete all your notes and settings locally. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError),
            onPressed: () {
              context.read<SettingsBloc>().add(ResetAllDataEvent());
              Navigator.pop(context);
            },
            child: const Text('Clear Everything'),
          ),
        ],
      ),
    );
  }
}
