import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 10, bottom: 10 + bottomPadding),
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
              selectedIcon: Icons.note_rounded,
              label: 'Notes',
              isSelected: selectedIndex == 0,
              onTap: () => onIndexChanged(0),
              color: color,
              textTheme: textTheme,
            ),
            _NavItem(
              icon: Icons.notifications_none_rounded,
              selectedIcon: Icons.notifications_rounded,
              label: 'Remind',
              isSelected: selectedIndex == 1,
              onTap: () => onIndexChanged(1),
              color: color,
              textTheme: textTheme,
            ),
            _AddButton(
              onPressed: addNote,
              color: color,
            ),
            _NavItem(
              icon: Icons.archive_outlined,
              selectedIcon: Icons.archive_rounded,
              label: 'Archive',
              isSelected: selectedIndex == 3,
              onTap: () => onIndexChanged(3),
              color: color,
              textTheme: textTheme,
            ),
            _NavItem(
              icon: Icons.delete_outline_rounded,
              selectedIcon: Icons.delete_rounded,
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

class _NavItem extends StatefulWidget {
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
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 0.9), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 40),
    ]).animate(CurvedAnimation(parent: _bounceController, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant _NavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _bounceController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? widget.color.primary.withAlpha(30)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _bounceAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _bounceAnimation.value,
                  child: child,
                );
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: Icon(
                  widget.isSelected ? widget.selectedIcon : widget.icon,
                  key: ValueKey(widget.isSelected),
                  size: 22,
                  color: widget.isSelected
                      ? widget.color.primary
                      : widget.color.onSurface.withAlpha(150),
                ),
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: widget.textTheme.labelSmall!.copyWith(
                fontSize: 10,
                color: widget.isSelected
                    ? widget.color.primary
                    : widget.color.onSurface.withAlpha(150),
                fontWeight:
                    widget.isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              child: Text(widget.label),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatefulWidget {
  const _AddButton({
    required this.onPressed,
    required this.color,
  });

  final VoidCallback onPressed;
  final ColorScheme color;

  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotateAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _rotateAnimation = Tween<double>(begin: 0.0, end: 0.125).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.85), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.1), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        _controller.forward(from: 0);
        widget.onPressed();
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Transform.rotate(
              angle: _rotateAnimation.value * 3.14159 * 2,
              child: child,
            ),
          );
        },
        child: Container(
          height: 46,
          width: 46,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.color.primary,
                widget.color.primary.withAlpha(200),
              ],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.primary.withAlpha(100),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            Icons.add_rounded,
            color: widget.color.onPrimary,
            size: 26,
          ),
        ),
      ),
    );
  }
}
