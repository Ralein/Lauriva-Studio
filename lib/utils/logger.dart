import 'package:flutter/foundation.dart';

/// Enterprise logging utility for Lauriva.
///
/// - Debug/info/warn are silenced in release builds.
/// - error() always logs — critical failures must be visible in release.
/// - fatal() additionally reports via FlutterError so crash-reporting hooks fire.
/// - A capped in-memory ring buffer holds the last 50 error/fatal entries for
///   self-diagnosis (no PII — only message + tag, no stack traces stored).
class AppLogger {
  AppLogger._();

  static const int _ringBufferCapacity = 50;
  static final List<LogEntry> _errorRingBuffer = [];

  /// Read-only view of recent error entries for diagnostics.
  static List<LogEntry> get recentErrors =>
      List.unmodifiable(_errorRingBuffer);

  static void _appendToBuffer(String level, String message, String? tag) {
    if (_errorRingBuffer.length >= _ringBufferCapacity) {
      _errorRingBuffer.removeAt(0);
    }
    _errorRingBuffer.add(LogEntry(
      level: level,
      message: message,
      tag: tag,
      timestamp: DateTime.now(),
    ));
  }

  static void debug(String message, [String? tag]) {
    if (kDebugMode) {
      final prefix = tag != null ? '[$tag] ' : '';
      debugPrint('[DEBUG] $prefix$message');
    }
  }

  static void info(String message, [String? tag]) {
    if (kDebugMode) {
      final prefix = tag != null ? '[$tag] ' : '';
      debugPrint('[INFO] $prefix$message');
    }
  }

  static void warn(String message, [String? tag]) {
    if (kDebugMode) {
      final prefix = tag != null ? '[$tag] ' : '';
      debugPrint('[WARN] $prefix$message');
    }
  }

  /// Logs an error — always visible even in release mode (no PII printed).
  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? tag,
  }) {
    final prefix = tag != null ? '[$tag] ' : '';
    // Always log errors — silent release crashes are unacceptable.
    debugPrint('[ERROR] $prefix$message');
    if (kDebugMode) {
      if (error != null) debugPrint('Exception: $error');
      if (stackTrace != null) debugPrint('StackTrace: $stackTrace');
    }
    _appendToBuffer('ERROR', message, tag);
  }

  /// Logs a fatal error and reports it through FlutterError so any
  /// crash-reporting integration (Sentry, Firebase Crashlytics, etc.) fires.
  static void fatal(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? tag,
  }) {
    final prefix = tag != null ? '[$tag] ' : '';
    debugPrint('[FATAL] $prefix$message');
    if (error != null) debugPrint('FatalException: $error');
    _appendToBuffer('FATAL', message, tag);

    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error ?? Exception(message),
        stack: stackTrace,
        library: 'Lauriva',
        context: ErrorDescription('$prefix$message'),
      ),
    );
  }

  /// Sanitizes sensitive strings (e.g. API keys) before displaying or logging.
  static String maskApiKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length <= 8) return '••••••••';
    return '${trimmed.substring(0, 4)}••••••••${trimmed.substring(trimmed.length - 4)}';
  }
}

/// An entry in the in-memory error ring buffer.
class LogEntry {
  final String level;
  final String message;
  final String? tag;
  final DateTime timestamp;

  const LogEntry({
    required this.level,
    required this.message,
    required this.tag,
    required this.timestamp,
  });
}
