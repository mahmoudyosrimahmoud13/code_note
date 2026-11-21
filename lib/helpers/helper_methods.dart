import 'package:flutter/material.dart';
import 'package:uuid/v4.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
const uuid = UuidV4();

enum SnackType { success, faild }

void showMessage(
    {required String message, SnackType type = SnackType.success}) {
  final context = navigatorKey.currentContext;
  if (context == null) return;
  final failed = type == SnackType.faild;
  final color = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        // Shape, margin and colors come from the app theme.
        backgroundColor: failed ? color.error : null,
        duration: Duration(seconds: failed ? 5 : 3),
        content: Row(
          children: [
            Icon(
              failed ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              size: 20,
              color: failed ? color.onError : const Color(0xFFB3A2FF),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message,
                  style: failed ? TextStyle(color: color.onError) : null),
            ),
          ],
        ),
      ),
    );
}

void navigateTo(
    {required Widget toPage, bool dontRemove = true, bool replace = false}) {
  if (!replace) {
    Navigator.pushAndRemoveUntil(
      navigatorKey.currentContext!,
      MaterialPageRoute(
        builder: (context) => toPage,
      ),
      (route) => dontRemove,
    );
  } else {
    Navigator.pushReplacement(
      navigatorKey.currentContext!,
      MaterialPageRoute(
        builder: (context) {
          return toPage;
        },
      ),
    );
  }
}
bool isValidEmail(String email) {
  return RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+")
      .hasMatch(email);
}
