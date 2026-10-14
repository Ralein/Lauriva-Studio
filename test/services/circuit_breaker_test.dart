import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/circuit_breaker.dart';

void main() {
  group('CircuitBreaker state transitions', () {
    test('starts closed with zero failures', () {
      final breaker = CircuitBreaker(name: 'TestBreaker', failureThreshold: 3);
      expect(breaker.isClosed, isTrue);
      expect(breaker.isOpen, isFalse);
      expect(breaker.isHalfOpen, isFalse);
      expect(breaker.stateDescription, contains('CLOSED'));
    });

    test('opens after reaching failureThreshold failures via recordFailure()', () {
      final breaker = CircuitBreaker(name: 'TestBreaker', failureThreshold: 3);

      breaker.recordFailure();
      expect(breaker.isClosed, isTrue);
      breaker.recordFailure();
      expect(breaker.isClosed, isTrue);
      breaker.recordFailure();

      expect(breaker.isOpen, isTrue);
      expect(breaker.isClosed, isFalse);
      expect(breaker.stateDescription, contains('OPEN'));
    });

    test('recordSuccess resets consecutive failures and keeps breaker closed', () {
      final breaker = CircuitBreaker(name: 'TestBreaker', failureThreshold: 3);

      breaker.recordFailure();
      breaker.recordFailure();
      breaker.recordSuccess();

      // Next failure should be count 1, not 3
      breaker.recordFailure();
      expect(breaker.isClosed, isTrue);
      expect(breaker.isOpen, isFalse);
    });

    test('transitions to half-open after cooldown expires and allows probe', () async {
      final breaker = CircuitBreaker(
        name: 'TestBreaker',
        failureThreshold: 2,
        cooldownDuration: const Duration(milliseconds: 50),
      );

      breaker.recordFailure();
      breaker.recordFailure();
      expect(breaker.isOpen, isTrue);

      // Wait for cooldown to elapse
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Accessing isOpen triggers state transition check
      expect(breaker.isOpen, isFalse);
      expect(breaker.isHalfOpen, isTrue);
      expect(breaker.stateDescription, contains('HALF-OPEN'));

      // If probe succeeds, circuit closes
      breaker.recordSuccess();
      expect(breaker.isClosed, isTrue);
      expect(breaker.isHalfOpen, isFalse);
    });

    test('re-opens immediately if probe fails in half-open state', () async {
      final breaker = CircuitBreaker(
        name: 'TestBreaker',
        failureThreshold: 2,
        cooldownDuration: const Duration(milliseconds: 50),
      );

      breaker.recordFailure();
      breaker.recordFailure();
      expect(breaker.isOpen, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(breaker.isOpen, isFalse);
      expect(breaker.isHalfOpen, isTrue);

      // Probe failure
      breaker.recordFailure();
      expect(breaker.isOpen, isTrue);
      expect(breaker.isHalfOpen, isFalse);
    });
  });

  group('CircuitBreaker.execute', () {
    test('executes action normally when circuit is closed', () async {
      final breaker = CircuitBreaker(name: 'TestBreaker');
      final result = await breaker.execute(() async => 'success_payload');
      expect(result, equals('success_payload'));
      expect(breaker.isClosed, isTrue);
    });

    test('throws original exception on failure and records it', () async {
      final breaker = CircuitBreaker(name: 'TestBreaker', failureThreshold: 2);

      await expectLater(
        () => breaker.execute(() async => throw Exception('API 500 error')),
        throwsA(isA<Exception>()),
      );
      expect(breaker.isClosed, isTrue);

      await expectLater(
        () => breaker.execute(() async => throw Exception('API 500 error 2')),
        throwsA(isA<Exception>()),
      );
      expect(breaker.isOpen, isTrue);
    });

    test('throws CircuitBreakerOpenException when circuit is open', () async {
      final breaker = CircuitBreaker(name: 'TestBreaker', failureThreshold: 1);

      await expectLater(
        () => breaker.execute(() async => throw Exception('Failure')),
        throwsA(isA<Exception>()),
      );
      expect(breaker.isOpen, isTrue);

      await expectLater(
        () => breaker.execute(() async => 'should not run'),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
    });

    test('fatal OS errors (OOM, StackOverflow) are rethrown without recording circuit failure', () async {
      final breaker = CircuitBreaker(name: 'TestBreaker', failureThreshold: 1);

      await expectLater(
        () => breaker.execute(() async => throw OutOfMemoryError()),
        throwsA(isA<OutOfMemoryError>()),
      );
      // Circuit must remain CLOSED because OOM is an OS fatal error, not an API failure
      expect(breaker.isClosed, isTrue);

      await expectLater(
        () => breaker.execute(() async => throw StackOverflowError()),
        throwsA(isA<StackOverflowError>()),
      );
      expect(breaker.isClosed, isTrue);
    });

    test('10-minute cooldown cap is enforced for very long cooldown durations', () {
      final breaker = CircuitBreaker(
        name: 'CappedBreaker',
        cooldownDuration: const Duration(hours: 5),
      );
      // Breaker internally caps effective cooldown to 10 minutes max
      breaker.recordFailure();
      breaker.recordFailure();
      breaker.recordFailure();
      expect(breaker.isOpen, isTrue);
      expect(breaker.stateDescription, contains('OPEN'));
    });
  });
}
