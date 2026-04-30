import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/settings.dart';
import '../bloc/settings_bloc.dart';
import '../bloc/settings_event.dart';

class ProfileEditPage extends StatefulWidget {
  final SettingsEntity settings;
  const ProfileEditPage({super.key, required this.settings});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  late TextEditingController _nameController;
  late TextEditingController _handleController;
  late TextEditingController _aboutController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.settings.userName);
    _handleController = TextEditingController(text: widget.settings.userHandle);
    _aboutController = TextEditingController(text: widget.settings.about ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _handleController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  void _save() {
    final String name = _nameController.text.trim();
    final String username = _handleController.text.trim().toLowerCase();
    final String about = _aboutController.text.trim();

    final updatedSettings = widget.settings.copyWith(
      userName: name,
      userHandle: username,
      about: about,
    );

    context.read<SettingsBloc>().add(UpdateSettingsEvent(updatedSettings));
    
    Navigator.pop(context, true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated locally!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFieldTitle('Display Name', text, color),
            const SizedBox(height: 8),
            _buildTextField(_nameController, 'Enter your name'),
            const SizedBox(height: 24),
            _buildFieldTitle('Username', text, color),
            const SizedBox(height: 8),
            _buildTextField(
              _handleController,
              'Enter your username',
              prefix: '@',
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'[A-Z]')),
              ],
            ),
            const SizedBox(height: 24),
            _buildFieldTitle('About', text, color),
            const SizedBox(height: 8),
            _buildTextField(_aboutController, 'Tell something about yourself...', maxLines: 5),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldTitle(String title, TextTheme text, ColorScheme color) {
    return Text(
      title,
      style: text.labelLarge!.copyWith(color: color.primary, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, {String? prefix, int maxLines = 1, List<TextInputFormatter>? inputFormatters}) {
    final color = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: color.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.outlineVariant.withAlpha(50)),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          hintText: hint,
          prefixText: prefix,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}
