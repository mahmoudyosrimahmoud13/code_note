import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'pyodide_runtime.dart';

/// Keeps Python's web view alive behind the app: 1×1 pixel, invisible and
/// not touchable. It's only built once a phone runs its first Python block.
class PyodideHost extends StatelessWidget {
  const PyodideHost({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WebViewController?>(
      valueListenable: PyodideRuntime.instance.controller,
      builder: (context, controller, _) {
        if (controller == null) return const SizedBox.shrink();
        return Positioned(
          left: 0,
          top: 0,
          width: 1,
          height: 1,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Opacity(opacity: 0.01, child: WebViewWidget(controller: controller)),
            ),
          ),
        );
      },
    );
  }
}
