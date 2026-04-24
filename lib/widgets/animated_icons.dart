import 'package:flutter/material.dart';

/// A widget that wraps an icon with a subtle pulse animation.
/// Used for reminder bells and other attention-seeking icons.
class PulsingIcon extends StatefulWidget {
  const PulsingIcon({
    super.key,
    required this.icon,
    required this.size,
    required this.color,
  });

  final IconData icon;
  final double size;
  final Color color;

  @override
  State<PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: Opacity(
            opacity: 0.6 + (_animation.value * 0.4),
            child: child,
          ),
        );
      },
      child: Icon(widget.icon, size: widget.size, color: widget.color),
    );
  }
}

/// A widget that gives an icon a gentle glowing effect.
/// Used for the code block indicator on note cards.
class GlowingIcon extends StatefulWidget {
  const GlowingIcon({
    super.key,
    required this.icon,
    required this.size,
    required this.color,
    this.glowColor,
  });

  final IconData icon;
  final double size;
  final Color color;
  final Color? glowColor;

  @override
  State<GlowingIcon> createState() => _GlowingIconState();
}

class _GlowingIconState extends State<GlowingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.0, end: 6.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: widget.color.withAlpha(20),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (widget.glowColor ?? widget.color).withAlpha(30),
                blurRadius: _animation.value,
                spreadRadius: _animation.value * 0.3,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Icon(widget.icon, size: widget.size, color: widget.color.withAlpha(180)),
    );
  }
}

/// A bouncy badge for showing pinned status.
class AnimatedPinBadge extends StatefulWidget {
  const AnimatedPinBadge({super.key});

  @override
  State<AnimatedPinBadge> createState() => _AnimatedPinBadgeState();
}

class _AnimatedPinBadgeState extends State<AnimatedPinBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
    _rotateAnimation = Tween<double>(begin: -0.05, end: 0.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _rotateAnimation,
      builder: (context, child) {
        return Transform.rotate(
          angle: _rotateAnimation.value,
          child: child,
        );
      },
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.amber.shade400, Colors.orange.shade300],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.amber.withAlpha(60),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.star_rounded,
          size: 12,
          color: color.surface,
        ),
      ),
    );
  }
}

/// A wrapper that adds a scale bounce animation when the icon changes or is tapped.
class BouncyIcon extends StatefulWidget {
  const BouncyIcon({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
  });

  final Widget child;
  final Duration duration;

  @override
  State<BouncyIcon> createState() => _BouncyIconState();
}

class _BouncyIconState extends State<BouncyIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant BouncyIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Transform.scale(
        scale: _animation.value,
        child: child,
      ),
      child: widget.child,
    );
  }
}

