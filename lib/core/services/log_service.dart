import 'package:flutter/foundation.dart';

class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  final List<String> _logs = [];
  
  void log(String message) {
    final timestamp = DateTime.now().toString().split('.').first;
    final logMessage = "[$timestamp] $message";
    _logs.add(logMessage);
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }
    debugPrint(logMessage);
  }

  List<String> get logs => List.unmodifiable(_logs);
  
  void clear() {
    _logs.clear();
  }
}
