import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomIconButton extends StatefulWidget {
  const CustomIconButton({
    super.key,
    this.icon,
    this.text,
    this.borderColor,
    this.innerColor,
    this.iconColor,
    this.iconSize,
    this.onPressed,
  });

  final IconData? icon;
  final String? text;
  final void Function()? onPressed;
  final Color? borderColor;
  final Color? innerColor;
  final Color? iconColor;
  final double? iconSize;

  @override
  State<CustomIconButton> createState() => _CustomIconButtonState();
}

class _CustomIconButtonState extends State<CustomIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails _) {
    _controller.reverse();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    final effectiveIconSize = widget.iconSize ?? 25;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onPressed?.call();
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: SizedBox(
          height: effectiveIconSize + 25,
          child: ElevatedButton(
            onPressed: null, // Handled by GestureDetector
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.innerColor ?? color.surface,
              disabledBackgroundColor: widget.innerColor ?? color.surface,
              shape: CircleBorder(
                side: BorderSide(
                  width: 1,
                  color: widget.borderColor ?? color.onSurface.withAlpha(80),
                ),
              ),
              elevation: 0,
            ),
            child: widget.icon == null
                ? Text(
                    widget.text!,
                    style: textTheme.bodyLarge!.copyWith(
                      fontWeight: FontWeight.bold,
                      color: widget.iconColor ?? color.primary,
                    ),
                  )
                : Icon(
                    widget.icon,
                    color: widget.iconColor ?? color.primary,
                    size: effectiveIconSize,
                  ),
          ),
        ),
      ),
    );
  }
}
