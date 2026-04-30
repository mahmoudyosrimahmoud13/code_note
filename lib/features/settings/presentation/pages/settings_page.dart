import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

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
                      'Theme Mode',
                      settings.themeMode.toUpperCase(),
                      Icons.palette_rounded,
                      Colors.orange,
                      trailing: DropdownButton<String>(
                        value: settings.themeMode,
                        underline: const SizedBox(),
                        items: ['light', 'dark', 'system']
                            .map((v) => DropdownMenuItem(
                                value: v, child: Text(v.toUpperCase())))
                            .toList(),
                        onChanged: (v) => v != null
                            ? context.read<SettingsBloc>().add(
                                UpdateSettingsEvent(
                                    settings.copyWith(themeMode: v)))
                            : null,
                      ),
                      color: color,
                    ),
                    const SizedBox(height: 16),
                    _buildSettingTile(
                      'Font Size',
                      'Scale: ${settings.fontSizeMultiplier.toStringAsFixed(1)}x',
                      Icons.format_size_rounded,
                      Colors.blue,
                      bottom: Slider(
                        value: settings.fontSizeMultiplier,
                        min: 0.8,
                        max: 1.5,
                        divisions: 7,
                        onChanged: (v) => context.read<SettingsBloc>().add(
                            UpdateSettingsEvent(
                                settings.copyWith(fontSizeMultiplier: v))),
                      ),
                      color: color,
                    ),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Management', textTheme, color),
                    const SizedBox(height: 16),
                    _buildSettingTile(
                        'Clear All Data',
                        'Delete all local notes and settings',
                        Icons.delete_forever_rounded,
                        Colors.red,
                        onTap: () => _showClearDataConfirmation(context),
                        color: color),
                    const SizedBox(height: 32),
                    _buildSectionHeader('About', textTheme, color),
                    const SizedBox(height: 16),
                    _buildSettingTile(
                      'GitHub Project',
                      'View source and contribute',
                      Icons.code_rounded,
                      Colors.purple,
                      onTap: () => launchUrl(Uri.parse(
                          'https://github.com/mahmoudyosrimahmoud13/code_note')),
                      color: color,
                    ),
                    const SizedBox(height: 16),
                    _buildSettingTile(
                      'Version',
                      '1.2.0 (Open Source)',
                      Icons.info_rounded,
                      Colors.teal,
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
        color: color.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(32),
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
                      child: CircleAvatar(
                          backgroundColor: color.primary,
                          radius: 16,
                          child: const Icon(Icons.camera_alt,
                              size: 14, color: Colors.white)),
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
    return Text(title,
        style: textTheme.titleMedium!.copyWith(
          color: color.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ));
  }

  Widget _buildSettingTile(String title, String subtitle, IconData icon, Color iconColor,
      {Widget? trailing, Widget? bottom, VoidCallback? onTap, required ColorScheme color}) {
    return Container(
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withAlpha(50),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: iconColor.withAlpha(25),
                      child: Icon(icon, color: iconColor),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
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
