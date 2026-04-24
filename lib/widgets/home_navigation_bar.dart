import 'package:flutter/material.dart';

class NavBar extends StatelessWidget {
  const NavBar({
    super.key,
    required this.addNote,
    required this.selectedIndex,
    required this.onIndexChanged,
  });
  final void Function() addNote;
  final int selectedIndex;
  final void Function(int) onIndexChanged;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: color.surface.withAlpha(240),
          borderRadius: BorderRadius.circular(60),
          border: Border.all(
            color: color.primary.withAlpha(30),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.shadow.withAlpha(20),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _NavItem(
              icon: Icons.note_outlined,
              selectedIcon: Icons.note,
              label: 'Notes',
              isSelected: selectedIndex == 0,
              onTap: () => onIndexChanged(0),
              color: color,
              textTheme: textTheme,
            ),
            _NavItem(
              icon: Icons.notifications_none,
              selectedIcon: Icons.notifications,
              label: 'Remind',
              isSelected: selectedIndex == 1,
              onTap: () => onIndexChanged(1),
              color: color,
              textTheme: textTheme,
            ),
            // Center Add button
            _AddButton(
              onPressed: addNote,
              color: color,
            ),
            _NavItem(
              icon: Icons.archive_outlined,
              selectedIcon: Icons.archive,
              label: 'Archive',
              isSelected: selectedIndex == 3,
              onTap: () => onIndexChanged(3),
              color: color,
              textTheme: textTheme,
            ),
            _NavItem(
              icon: Icons.delete_outline,
              selectedIcon: Icons.delete,
              label: 'Trash',
              isSelected: selectedIndex == 4,
              onTap: () => onIndexChanged(4),
              color: color,
              textTheme: textTheme,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.color,
    required this.textTheme,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme color;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.primary.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              size: 22,
              color: isSelected ? color.primary : color.onSurface.withAlpha(150),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: textTheme.labelSmall!.copyWith(
                fontSize: 10,
                color: isSelected ? color.primary : color.onSurface.withAlpha(150),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.onPressed,
    required this.color,
  });

  final VoidCallback onPressed;
  final ColorScheme color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 44,
        width: 44,
        decoration: BoxDecoration(
          color: color.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.primary.withAlpha(80),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.add,
          color: color.onPrimary,
          size: 24,
        ),
      ),
    );
  }
}
