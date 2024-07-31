import 'package:flutter/material.dart';
import 'package:uuid/v4.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
const uuid = UuidV4();

enum MessageType { success, faild }

void showMessage(
    {required String message, MessageType type = MessageType.success}) {
  ScaffoldMessenger.of(navigatorKey.currentContext!).removeCurrentSnackBar();

  ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
    SnackBar(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15), // Adjust the radius as needed
      ),
      margin: const EdgeInsets.all(20),
      backgroundColor: type == MessageType.success
          ? Theme.of(navigatorKey.currentContext!).colorScheme.primary
          : Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      content: Column(
        children: [
          Text(message),
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
