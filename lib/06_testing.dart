/// Lesson 06 — Testing with Zones
///
/// Topics:
///   - Capturing errors in tests without crashing the test runner
///   - Fake/controllable timers using zone timer interception
///   - Capturing print output in tests
///   - Zone-based test isolation
///   - Integration with package:test (conceptual examples)
///
/// Run: dart run lib/06_testing.dart
///
/// Note: These examples demonstrate the zone techniques used by test frameworks.
/// In real tests, prefer package:test's `fakeAsync` and `expectAsync*` helpers
/// which are built on the same zone primitives shown here.

import 'dart:async';
import 'dart:collection';

void main() async {
  print('=== Lesson 06: Testing with Zones ===\n');

  await example1_captureErrors();
  await example2_capturePrint();
  example3_fakeTimers();
  await example4_testIsolation();
  await example5_miniTestHarness();
}

// ---------------------------------------------------------------------------
// Example 1: Capturing errors instead of crashing
// ---------------------------------------------------------------------------
Future<void> example1_captureErrors() async {
  print('--- Example 1: Capture errors ---');

  List<Object> capturedErrors = [];

  await runZonedGuarded(
    () async {
      // These would normally crash the test.
      Future.error(StateError('async error 1'));
      Future.error(ArgumentError('async error 2'));
      await Future.delayed(const Duration(milliseconds: 10));
    },
    (error, stack) => capturedErrors.add(error),
  );

  print('Captured ${capturedErrors.length} errors');
  for (final e in capturedErrors) {
    print('  - ${e.runtimeType}: $e');
  }

  // Assert pattern — useful in tests.
  assert(capturedErrors.length == 2, 'Expected 2 errors');
  assert(capturedErrors[0] is StateError);
  assert(capturedErrors[1] is ArgumentError);
  print('All assertions passed');
  print('');
}

// ---------------------------------------------------------------------------
// Example 2: Capturing print output
// ---------------------------------------------------------------------------
Future<void> example2_capturePrint() async {
  print('--- Example 2: Capture print ---');

  final lines = <String>[];

  await Zone.current.fork(
    specification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  ).run(() async {
    print('line A');
    await Future.delayed(Duration.zero);
    print('line B');
  });

  // Now assert on output without it polluting test output.
  assert(lines.length == 2);
  assert(lines[0] == 'line A');
  assert(lines[1] == 'line B');
  print('Captured lines: $lines');
  print('');
}

// ---------------------------------------------------------------------------
// Example 3: Fake timers — control time in tests
//
// This is a simplified version of what fakeAsync() in package:test does.
// ---------------------------------------------------------------------------

class FakeClock {
  Duration _elapsed = Duration.zero;
  final _pending = SplayTreeMap<Duration, List<void Function()>>(
    (a, b) => a.compareTo(b),
  );

  void elapse(Duration duration) {
    final target = _elapsed + duration;
    while (_pending.isNotEmpty && _pending.firstKey()! <= target) {
      _elapsed = _pending.firstKey()!;
      final callbacks = _pending.remove(_elapsed)!;
      for (final cb in callbacks) {
        cb();
      }
    }
    _elapsed = target;
  }

  Timer _createTimer(Duration delay, void Function() callback) {
    final fireAt = _elapsed + delay;
    _pending.putIfAbsent(fireAt, () => []).add(callback);
    return _FakeTimer(() => _pending[fireAt]?.remove(callback));
  }

  ZoneSpecification get spec => ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          return _createTimer(duration, callback);
        },
      );
}

class _FakeTimer implements Timer {
  final void Function() _cancel;
  _FakeTimer(this._cancel);
  @override
  void cancel() => _cancel();
  @override
  bool get isActive => false;
  @override
  int get tick => 0;
}

void example3_fakeTimers() {
  print('--- Example 3: Fake timers ---');

  final clock = FakeClock();
  final log = <String>[];

  Zone.current.fork(specification: clock.spec).run(() {
    Timer(const Duration(seconds: 1), () => log.add('1s fired'));
    Timer(const Duration(seconds: 3), () => log.add('3s fired'));
    Timer(const Duration(seconds: 2), () => log.add('2s fired'));
  });

  print('t=0: $log'); // []

  clock.elapse(const Duration(seconds: 1));
  print('t=1s: $log'); // [1s fired]

  clock.elapse(const Duration(seconds: 1));
  print('t=2s: $log'); // [1s fired, 2s fired]

  clock.elapse(const Duration(seconds: 1));
  print('t=3s: $log'); // [1s fired, 2s fired, 3s fired]

  assert(log.length == 3);
  print('');
}

// ---------------------------------------------------------------------------
// Example 4: Test isolation — each test runs in its own zone
// ---------------------------------------------------------------------------
Future<void> example4_testIsolation() async {
  print('--- Example 4: Test isolation ---');

  // Simulate a global-ish counter that we want isolated per test.
  int counter = 0;
  final counterKey = Object();

  Future<void> runTest(String name, Future<void> Function() body) async {
    final errors = <Object>[];

    // runZonedGuarded's onError only catches *uncaught zone* errors.
    // Errors thrown by async functions come back as rejected Futures, so we
    // also need a try/catch around the awaited body.
    await runZonedGuarded(
      () async {
        try {
          await Zone.current
              .fork(zoneValues: {counterKey: 0}) // fresh counter per test
              .run(body);
        } catch (e) {
          // Catches rejections from the async body (e.g. throw inside async fn).
          errors.add(e);
        }
      },
      (e, s) => errors.add(e), // catches fire-and-forget Future errors
    );

    final status = errors.isEmpty ? 'PASS' : 'FAIL';
    print('[$status] $name'
        '${errors.isNotEmpty ? " — ${errors.first}" : ""}');

    // Reset global state between tests.
    counter = 0;
  }

  await runTest('counter starts at zero', () async {
    final c = Zone.current[counterKey] as int;
    assert(c == 0, 'expected 0, got $c');
  });

  await runTest('intentionally failing test', () async {
    throw AssertionError('simulated failure');
  });

  await runTest('async test with delay', () async {
    await Future.delayed(Duration.zero);
    final c = Zone.current[counterKey] as int;
    assert(c == 0);
  });

  print('');
}

// ---------------------------------------------------------------------------
// Example 5: A tiny synchronous test harness built on zones
// ---------------------------------------------------------------------------

class MiniTest {
  int _pass = 0;
  int _fail = 0;

  void test(String name, void Function() body) {
    final errors = <Object>[];

    runZonedGuarded(body, (e, s) => errors.add(e));

    if (errors.isEmpty) {
      _pass++;
      print('  ✓ $name');
    } else {
      _fail++;
      print('  ✗ $name — ${errors.first}');
    }
  }

  void report() {
    print('\nResults: $_pass passed, $_fail failed');
  }
}

Future<void> example5_miniTestHarness() async {
  print('--- Example 5: Mini test harness ---');

  final suite = MiniTest();

  suite.test('addition works', () {
    final result = 2 + 2;
    if (result != 4) throw AssertionError('$result != 4');
  });

  suite.test('string reversal', () {
    final reversed = 'hello'.split('').reversed.join();
    if (reversed != 'olleh') throw AssertionError('$reversed != olleh');
  });

  suite.test('this test will fail', () {
    throw StateError('intentional failure');
  });

  suite.test('list length', () {
    final list = [1, 2, 3];
    if (list.length != 3) throw AssertionError('unexpected length');
  });

  suite.report();
  print('');
}
