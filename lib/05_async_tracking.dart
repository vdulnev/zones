/// Lesson 05 — Async Tracking and Performance Monitoring
///
/// Topics:
///   - Counting in-flight async operations
///   - Measuring timer latency drift
///   - Building a simple profiler with zones
///   - Detecting long microtask queues
///   - Zone-aware structured logging
///
/// Run: dart run lib/05_async_tracking.dart

import 'dart:async';

void main() async {
  print('=== Lesson 05: Async Tracking & Monitoring ===\n');

  await example1_inflightCounter();
  await example2_timerLatency();
  await example3_profiler();
  await example4_microtaskDetector();
  await example5_structuredLogging();
}

// ---------------------------------------------------------------------------
// Example 1: Counting in-flight async operations
//
// Useful to know when your app is "idle" (counter == 0).
// ---------------------------------------------------------------------------
Future<void> example1_inflightCounter() async {
  print('--- Example 1: In-flight counter ---');

  int inFlight = 0;

  Future<T> tracked<T>(Future<T> future) {
    inFlight++;
    return future.whenComplete(() => inFlight--);
  }

  Zone.current.fork(
    specification: ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, f) {
        // Each microtask = one async unit of work.
        parent.scheduleMicrotask(zone, f);
      },
    ),
  );

  print('Before: in-flight=$inFlight');

  final futures = [
    tracked(Future.delayed(const Duration(milliseconds: 10), () => 'a')),
    tracked(Future.delayed(const Duration(milliseconds: 20), () => 'b')),
    tracked(Future.delayed(const Duration(milliseconds: 5), () => 'c')),
  ];

  print('After scheduling: in-flight=$inFlight');

  await Future.delayed(const Duration(milliseconds: 8));
  print('After 8ms: in-flight=$inFlight'); // 'c' done

  await Future.wait(futures);
  print('After all: in-flight=$inFlight'); // 0
  print('');
}

// ---------------------------------------------------------------------------
// Example 2: Timer latency drift
//
// Measures how much actual wall-clock time differs from the requested delay.
// ---------------------------------------------------------------------------
Future<void> example2_timerLatency() async {
  print('--- Example 2: Timer latency ---');

  final latencies = <int>[];

  final zone = Zone.current.fork(
    specification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        final scheduled = DateTime.now();
        return parent.createTimer(zone, duration, () {
          final actual = DateTime.now().difference(scheduled).inMicroseconds;
          final expected = duration.inMicroseconds;
          latencies.add(actual - expected);
          callback();
        });
      },
    ),
  );

  await zone.run(() async {
    // Schedule several timers with different durations.
    for (final ms in [5, 10, 15, 20, 25]) {
      Timer(Duration(milliseconds: ms), () {});
    }
    await Future.delayed(const Duration(milliseconds: 50));
  });

  if (latencies.isNotEmpty) {
    final avg = latencies.reduce((a, b) => a + b) ~/ latencies.length;
    print('Timers measured: ${latencies.length}');
    print('Avg latency drift: ${avg}µs');
    print('Max drift: ${latencies.reduce((a, b) => a > b ? a : b)}µs');
  }
  print('');
}

// ---------------------------------------------------------------------------
// Example 3: Simple profiler
//
// Wraps every registered callback to measure execution time.
// ---------------------------------------------------------------------------

class Profiler {
  final _timings = <String, List<int>>{};

  void record(String label, int microseconds) {
    _timings.putIfAbsent(label, () => []).add(microseconds);
  }

  void report() {
    for (final entry in _timings.entries) {
      final times = entry.value;
      final avg = times.reduce((a, b) => a + b) ~/ times.length;
      print('  ${entry.key}: calls=${times.length}, avg=${avg}µs');
    }
  }

  ZoneSpecification get spec => ZoneSpecification(
        registerCallback: <R>(self, parent, zone, f) {
          return parent.registerCallback(zone, () {
            final sw = Stopwatch()..start();
            final result = f();
            sw.stop();
            record('callback', sw.elapsedMicroseconds);
            return result;
          });
        },
        registerUnaryCallback: <R, T>(self, parent, zone, f) {
          return parent.registerUnaryCallback(zone, (T arg) {
            final sw = Stopwatch()..start();
            final result = f(arg);
            sw.stop();
            record('unaryCallback', sw.elapsedMicroseconds);
            return result;
          });
        },
      );
}

Future<void> example3_profiler() async {
  print('--- Example 3: Profiler ---');

  final profiler = Profiler();

  await Zone.current.fork(specification: profiler.spec).run(() async {
    // Some async work that registers callbacks.
    await Future.value(42).then((v) => v * 2);
    await Future.value('hello').then((s) => s.toUpperCase());
    await Future.delayed(Duration.zero).then((_) => 'done');
  });

  print('Profile report:');
  profiler.report();
  print('');
}

// ---------------------------------------------------------------------------
// Example 4: Detecting suspiciously long microtask queues
// ---------------------------------------------------------------------------
Future<void> example4_microtaskDetector() async {
  print('--- Example 4: Microtask queue depth ---');

  int queued = 0;
  int maxQueued = 0;

  final zone = Zone.current.fork(
    specification: ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, f) {
        queued++;
        if (queued > maxQueued) maxQueued = queued;
        parent.scheduleMicrotask(zone, () {
          try {
            f();
          } finally {
            queued--;
          }
        });
      },
    ),
  );

  await zone.run(() async {
    // Schedule a burst of microtasks.
    for (int i = 0; i < 20; i++) {
      scheduleMicrotask(() {});
    }
    await Future.delayed(Duration.zero);
    print('Max concurrent microtasks: $maxQueued');
    if (maxQueued > 10) {
      print('WARNING: high microtask queue depth detected!');
    }
  });

  print('');
}

// ---------------------------------------------------------------------------
// Example 5: Zone-aware structured logging
// ---------------------------------------------------------------------------

class StructuredLogger {
  final _key = Object();

  Zone scope(Map<String, Object?> context) => Zone.current.fork(
        zoneValues: {_key: {..._currentContext, ...context}},
      );

  Map<String, Object?> get _currentContext =>
      (Zone.current[_key] as Map<String, Object?>?) ?? {};

  void info(String message) {
    final ctx = _currentContext;
    final parts = [
      '"level":"INFO"',
      '"msg":"$message"',
      ...ctx.entries.map((e) => '"${e.key}":"${e.value}"'),
    ];
    print('{${parts.join(', ')}}');
  }
}

Future<void> example5_structuredLogging() async {
  print('--- Example 5: Structured logging ---');

  final logger = StructuredLogger();

  // Top-level context.
  await logger.scope({'service': 'payment-service', 'version': '2.1'}).run(
    () async {
      logger.info('service started');

      // Nested context for a specific request.
      await logger.scope({'requestId': 'abc-123', 'userId': '42'}).run(
        () async {
          logger.info('processing payment');
          await Future.delayed(Duration.zero);
          logger.info('payment complete');
        },
      );

      // Back to top-level context — no requestId.
      logger.info('ready for next request');
    },
  );

  print('');
}
