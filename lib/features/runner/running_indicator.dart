import 'package:flutter/material.dart';

import '../../constants/themes.dart';

/// ▶ when idle; ■ inside a spinning ring while something runs.
class RunButtonIcon extends StatelessWidget {
  const RunButtonIcon({super.key, required this.running, this.size = 20});
  final bool running;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (!running) return Icon(Icons.play_arrow_rounded, size: size, color: tokens.success);
    final ring = size + 6;
    return SizedBox(
      width: ring,
      height: ring,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: ring,
          height: ring,
          child: CircularProgressIndicator(strokeWidth: 2, color: tokens.success),
        ),
        Icon(Icons.stop_rounded, size: size - 4, color: Theme.of(context).colorScheme.error),
      ]),
    );
  }
}
