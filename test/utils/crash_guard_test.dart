import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/utils/crash_guard.dart';

void main() {
  group('CrashGuard.run', () {
    test('returns function result on success', () {
      final result = CrashGuard.run(() => 42, fallback: 0);
      expect(result, equals(42));
    });

    test('returns fallback on standard Exception', () {
      final result = CrashGuard.run<int>(
        () => throw Exception('Calculation error'),
        fallback: -1,
      );
      expect(result, equals(-1));
    });

    test('returns fallback on non-fatal Error (e.g. StateError, ArgumentError)', () {
      final result = CrashGuard.run<String>(
        () => throw StateError('Invalid state'),
        fallback: 'recovered',
      );
      expect(result, equals('recovered'));
    });

    test('rethrows OutOfMemoryError so OS/runtime can handle it', () {
      expect(
        () => CrashGuard.run(
          () => throw OutOfMemoryError(),
          fallback: 'unreachable',
        ),
        throwsA(isA<OutOfMemoryError>()),
      );
    });

    test('rethrows StackOverflowError so OS/runtime can handle it', () {
      expect(
        () => CrashGuard.run(
          () => throw StackOverflowError(),
          fallback: 'unreachable',
        ),
        throwsA(isA<StackOverflowError>()),
      );
    });
  });

  group('CrashGuard.runAsync', () {
    test('returns awaited result on success', () async {
      final result = await CrashGuard.runAsync(
        () async => 'hello async',
        fallback: 'fallback',
      );
      expect(result, equals('hello async'));
    });

    test('returns fallback on async Exception', () async {
      final result = await CrashGuard.runAsync<int>(
        () async => throw Exception('Network timeout'),
        fallback: 999,
      );
      expect(result, equals(999));
    });

    test('returns fallback on async non-fatal Error', () async {
      final result = await CrashGuard.runAsync<String>(
        () async => throw RangeError('Index out of bounds'),
        fallback: 'safe_value',
      );
      expect(result, equals('safe_value'));
    });

    test('rethrows OutOfMemoryError in async execution', () async {
      expect(
        () => CrashGuard.runAsync(
          () async => throw OutOfMemoryError(),
          fallback: 'unreachable',
        ),
        throwsA(isA<OutOfMemoryError>()),
      );
    });

    test('rethrows StackOverflowError in async execution', () async {
      expect(
        () => CrashGuard.runAsync(
          () async => throw StackOverflowError(),
          fallback: 'unreachable',
        ),
        throwsA(isA<StackOverflowError>()),
      );
    });
  });

  group('CrashGuard.runIsolate', () {
    test('returns result on success', () {
      final result = CrashGuard.runIsolate(
        () => 'isolate_result',
        fallback: 'fallback',
      );
      expect(result, equals('isolate_result'));
    });

    test('returns fallback on Exception without throwing', () {
      final result = CrashGuard.runIsolate(
        () => throw Exception('Isolate error'),
        fallback: 'safe_isolate',
      );
      expect(result, equals('safe_isolate'));
    });

    test('never rethrows even for OutOfMemoryError to avoid crashing background isolate', () {
      final result = CrashGuard.runIsolate(
        () => throw OutOfMemoryError(),
        fallback: 'isolate_fallback_oom',
      );
      expect(result, equals('isolate_fallback_oom'));
    });

    test('never rethrows even for StackOverflowError to avoid crashing background isolate', () {
      final result = CrashGuard.runIsolate(
        () => throw StackOverflowError(),
        fallback: 'isolate_fallback_so',
      );
      expect(result, equals('isolate_fallback_so'));
    });
  });
}
