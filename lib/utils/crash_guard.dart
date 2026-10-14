/// CrashGuard — Lauriva defensive execution wrappers.
///
/// Wraps synchronous and asynchronous computations to catch both [Exception]
/// and [Error] subclasses (including StackOverflowError, OutOfMemoryError,
/// TypeError). Fatal Errors that cannot be recovered from are rethrown after
/// logging; recoverable errors return the provided [fallback] value.
library;
import 'logger.dart';


class CrashGuard {
  CrashGuard._();

  /// Fatal error types that must never be swallowed — rethrown even inside
  /// silent catch blocks so the OS can handle them cleanly.
  static bool _isFatal(Object e) =>
      e is OutOfMemoryError || e is StackOverflowError;

  /// Synchronous guard. Calls [fn] and returns its result. On any error,
  /// returns [fallback] (or null if omitted). Fatal errors are rethrown.
  static T run<T>(
    T Function() fn, {
    T? fallback,
    String? tag,
  }) {
    try {
      return fn();
    } catch (e, st) {
      if (_isFatal(e)) rethrow;
      AppLogger.error(
        'CrashGuard.run caught: $e',
        error: e,
        stackTrace: st,
        tag: tag ?? 'CrashGuard',
      );
      return fallback as T;
    }
  }

  /// Asynchronous guard. Awaits [fn] and returns its result. On any error,
  /// returns [fallback] (or null if omitted). Fatal errors are rethrown.
  static Future<T> runAsync<T>(
    Future<T> Function() fn, {
    T? fallback,
    String? tag,
  }) async {
    try {
      return await fn();
    } catch (e, st) {
      if (_isFatal(e)) rethrow;
      AppLogger.error(
        'CrashGuard.runAsync caught: $e',
        error: e,
        stackTrace: st,
        tag: tag ?? 'CrashGuard',
      );
      return fallback as T;
    }
  }

  /// Isolate-safe synchronous guard — for use inside [compute()] callbacks
  /// where exceptions must be serialised as error sentinels rather than thrown.
  ///
  /// Returns either [fn]'s result or [fallback] on any error.
  /// Never rethrows (even for fatal errors) because isolate uncaught errors
  /// would be unhandled.
  static T runIsolate<T>(
    T Function() fn, {
    required T fallback,
    String? tag,
  }) {
    try {
      return fn();
    } catch (_) {
      return fallback;
    }
  }
}
