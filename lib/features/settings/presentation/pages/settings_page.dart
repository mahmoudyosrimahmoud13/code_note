import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bloc/settings_bloc.dart';
import '../bloc/settings_event.dart';
import '../bloc/settings_state.dart';
import '../../domain/entities/settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _nameController;
  late TextEditingController _handleController;

  @override
  void initState() {
    super.initState();
    final state = context.read<SettingsBloc>().state;
    if (state is SettingsLoaded) {
      _nameController = TextEditingController(text: state.settings.userName);
      _handleController = TextEditingController(text: state.settings.userHandle);
    } else {
      _nameController = TextEditingController();
      _handleController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _handleController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(SettingsEntity settings) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null && mounted) {
      context.read<SettingsBloc>().add(UpdateSettingsEvent(
        settings.copyWith(profileImagePath: image.path),
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
                    color.primaryContainer.withAlpha(30),
                  ],
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 120, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: color.surfaceContainerHighest.withAlpha(100),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: color.outlineVariant.withAlpha(50)),
                      ),
                      child: Column(
                        children: [
                          Center(
                            child: Stack(
                              children: [
                                Hero(
                                  tag: 'user_profile_photo',
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: color.primary, width: 3),
                                      boxShadow: [
                                        BoxShadow(
                                          color: color.primary.withAlpha(50),
                                          blurRadius: 20,
                                          spreadRadius: 5,
                                        )
                                      ],
                                    ),
                                    child: CircleAvatar(
                                      radius: 60,
                                      backgroundColor: color.primaryContainer,
                                      backgroundImage: settings.profileImagePath != null
                                          ? (kIsWeb 
                                              ? NetworkImage(settings.profileImagePath!) 
                                              : FileImage(File(settings.profileImagePath!))) as ImageProvider
                                          : const AssetImage('assets/stocks/profile.jpg'),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: GestureDetector(
                                    onTap: () => _pickImage(settings),
                                    child: CircleAvatar(
                                      backgroundColor: color.primary,
                                      radius: 18,
                                      child: const Icon(Icons.edit, size: 16, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildModernTextField(_nameController, 'Display Name', Icons.person, (val) {
                            context.read<SettingsBloc>().add(UpdateSettingsEvent(settings.copyWith(userName: val)));
                          }, color),
                          const SizedBox(height: 16),
                          _buildModernTextField(_handleController, 'Handle', Icons.alternate_email, (val) {
                            context.read<SettingsBloc>().add(UpdateSettingsEvent(settings.copyWith(userHandle: val)));
                          }, color),
                        ],
                      ),
                    ),

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
                        items: ['light', 'dark', 'system'].map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value.toUpperCase()),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            context.read<SettingsBloc>().add(UpdateSettingsEvent(settings.copyWith(themeMode: val)));
                          }
                        },
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
                        onChanged: (val) {
                          context.read<SettingsBloc>().add(UpdateSettingsEvent(settings.copyWith(fontSizeMultiplier: val)));
                        },
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
                      Colors.purple,
                      onTap: () => launchUrl(Uri.parse('https://github.com/mahmoudyosrimahmoud13/code_note')),
                      color: color,
                    ),
                    const SizedBox(height: 16),
                    _buildSettingTile(
                      'Version',
                      '1.0.0 (Premium Build)',
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

  Widget _buildModernTextField(TextEditingController controller, String label, IconData icon, Function(String) onChanged, ColorScheme color) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: color.primary),
        filled: true,
        fillColor: color.surface.withAlpha(150),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: color.primary, width: 1),
        ),
      ),
    );
  }

  Widget _buildSettingTile(String title, String subtitle, IconData icon, Color iconColor, {Widget? trailing, Widget? bottom, VoidCallback? onTap, required ColorScheme color}) {
    return Container(
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.outlineVariant.withAlpha(50)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: iconColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(subtitle, style: TextStyle(color: color.onSurfaceVariant, fontSize: 13)),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing,
                ],
              ),
              if (bottom != null) ...[
                const SizedBox(height: 8),
                bottom,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, TextTheme textTheme, ColorScheme color) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0),
      child: Text(
        title,
        style: textTheme.titleMedium!.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: color.primary.withAlpha(200),
        ),
      ),
    );
  }
}
