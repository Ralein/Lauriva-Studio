/// Circuit Breaker pattern for LLM API calls.
///
/// Prevents cascading failures and repeated hammering of an unavailable API.
/// After [failureThreshold] consecutive failures, the circuit opens and all
/// calls fail fast for [cooldownDuration]. After cooldown, moves to HALF_OPEN
/// state where a single probe call is allowed.
///
/// Phase 10: Replaces ad-hoc error handling in LlmService.
class CircuitBreaker {
  final int failureThreshold;
  final Duration cooldownDuration;
  final String name;

  int _consecutiveFailures = 0;
  _CircuitState _state = _CircuitState.closed;
  DateTime? _openedAt;

  CircuitBreaker({
    required this.name,
    this.failureThreshold = 3,
    this.cooldownDuration = const Duration(minutes: 2),
  });

  /// Returns true if the circuit is open and calls should fail fast.
  bool get isOpen {
    if (_state == _CircuitState.open) {
      final now = DateTime.now();
      if (_openedAt != null && now.difference(_openedAt!) >= _effectiveCooldown) {
        // Transition to half-open: allow one probe
        _state = _CircuitState.halfOpen;
        return false;
      }
      return true;
    }
    return false;
  }

  /// Returns true if the circuit is half-open (probe in progress).
  bool get isHalfOpen => _state == _CircuitState.halfOpen;

  /// Returns true if the circuit is closed (normal operation).
  bool get isClosed => _state == _CircuitState.closed;

  Duration? _customCooldown;

  // Cap maximum cooldown at 10 minutes so the breaker can never get stuck open forever.
  Duration get _effectiveCooldown =>
      _customCooldown ??
      (cooldownDuration > const Duration(minutes: 10)
          ? const Duration(minutes: 10)
          : cooldownDuration);

  /// Trips the circuit breaker open immediately with a specific cooldown duration.
  void tripWithCooldown(Duration duration) {
    _state = _CircuitState.open;
    _consecutiveFailures = failureThreshold;
    _openedAt = DateTime.now();
    _customCooldown = duration;
  }

  /// Call this when an API call succeeds.
  void recordSuccess() {
    _consecutiveFailures = 0;
    _state = _CircuitState.closed;
    _openedAt = null;
    _customCooldown = null;
  }

  /// Call this when an API call fails with a recoverable error.
  /// Fatal OS-level errors (OOM, StackOverflow) must NOT be recorded here —
  /// they should be rethrown by the caller without incrementing the counter.
  void recordFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= failureThreshold && _state == _CircuitState.closed) {
      _state = _CircuitState.open;
      _openedAt = DateTime.now();
    } else if (_state == _CircuitState.halfOpen) {
      // Probe failed — re-open
      _state = _CircuitState.open;
      _openedAt = DateTime.now();
    }
  }

  /// Executes [action] with circuit breaker protection.
  ///
  /// - Throws [CircuitBreakerOpenException] if the circuit is open.
  /// - Fatal OS errors ([OutOfMemoryError], [StackOverflowError]) are rethrown
  ///   immediately without recording a failure — these cannot be circuit-broken.
  /// - All other errors/exceptions increment the failure counter.
  Future<T> execute<T>(Future<T> Function() action) async {
    if (isOpen) {
      throw CircuitBreakerOpenException(
        'Circuit breaker "$name" is OPEN. Cooldown: ${_remainingCooldown().inSeconds}s remaining.',
      );
    }

    try {
      final result = await action();
      recordSuccess();
      return result;
    } on OutOfMemoryError {
      // Fatal — do not count as circuit failure; rethrow immediately.
      rethrow;
    } on StackOverflowError {
      // Fatal — do not count as circuit failure; rethrow immediately.
      rethrow;
    } catch (e) {
      recordFailure();
      rethrow;
    }
  }

  Duration _remainingCooldown() {
    if (_openedAt == null) return Duration.zero;
    final elapsed = DateTime.now().difference(_openedAt!);
    final remaining = _effectiveCooldown - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Human-readable state description.
  String get stateDescription {
    switch (_state) {
      case _CircuitState.closed:
        return 'CLOSED (normal)';
      case _CircuitState.open:
        return 'OPEN (failing fast — ${_remainingCooldown().inSeconds}s cooldown)';
      case _CircuitState.halfOpen:
        return 'HALF-OPEN (probing)';
    }
  }
}

enum _CircuitState { closed, open, halfOpen }

class CircuitBreakerOpenException implements Exception {
  final String message;
  const CircuitBreakerOpenException(this.message);

  @override
  String toString() => 'CircuitBreakerOpenException: $message';
}
