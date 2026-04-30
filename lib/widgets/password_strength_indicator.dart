import 'package:flutter/material.dart';

class PasswordStrengthIndicator extends StatelessWidget {
  final String password;

  const PasswordStrengthIndicator({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    final strength = _calculateStrength(password);
    final color = _getStrengthColor(strength);
    final label = _getStrengthLabel(strength);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Password Strength: ', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withAlpha(153))),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: strength,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            color: color,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 12),
        _buildRequirement('At least 8 characters', password.length >= 8, context),
        _buildRequirement('Contains uppercase & lowercase', _hasUpperAndLower(password), context),
        _buildRequirement('Contains a number', password.contains(RegExp(r'[0-9]')), context),
        _buildRequirement('Contains a special character', password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]')), context),
      ],
    );
  }

  Widget _buildRequirement(String label, bool isMet, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 14,
            color: isMet ? Colors.green : Theme.of(context).colorScheme.onSurface.withAlpha(102),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isMet ? Colors.green : Theme.of(context).colorScheme.onSurface.withAlpha(153),
            ),
          ),
        ],
      ),
    );
  }

  double _calculateStrength(String password) {
    if (password.isEmpty) return 0.0;
    double score = 0.0;
    if (password.length >= 8) score += 0.25;
    if (_hasUpperAndLower(password)) score += 0.25;
    if (password.contains(RegExp(r'[0-9]'))) score += 0.25;
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) score += 0.25;
    return score;
  }

  bool _hasUpperAndLower(String password) {
    return password.contains(RegExp(r'[A-Z]')) && password.contains(RegExp(r'[a-z]'));
  }

  Color _getStrengthColor(double strength) {
    if (strength <= 0.25) return Colors.red;
    if (strength <= 0.5) return Colors.orange;
    if (strength <= 0.75) return Colors.yellow;
    return Colors.green;
  }

  String _getStrengthLabel(double strength) {
    if (strength == 0) return 'None';
    if (strength <= 0.25) return 'Very Weak';
    if (strength <= 0.5) return 'Weak';
    if (strength <= 0.75) return 'Medium';
    return 'Strong';
  }
}
