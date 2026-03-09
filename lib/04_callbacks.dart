/// Lesson 04 — Intercepting Zone Callbacks
///
/// Topics:
///   - ZoneSpecification: the hook mechanism
///   - Intercepting print
///   - Intercepting scheduleMicrotask
///   - Intercepting Timer creation (createTimer / createPeriodicTimer)
///   - Intercepting registerCallback / registerUnaryCallback
///   - Combining multiple overrides
///
/// Run: dart run lib/04_callbacks.dart

import 'dart:async';

void main() async {
  print('=== Lesson 04: Zone Callbacks ===\n');

  await example1_interceptPrint();
  await example2_interceptMicrotask();
  await example3_interceptTimer();
  await example4_registerCallback();
  await example5_combined();
}

// ---------------------------------------------------------------------------
// Example 1: Intercepting print
// ---------------------------------------------------------------------------
Future<void> example1_interceptPrint() async {
  print('--- Example 1: Intercepting print ---');

  final buffer = StringBuffer();

  final zone = Zone.current.fork(
    specification: ZoneSpecification(
      print: (self, parent, zone, line) {
        // Prefix every print with a timestamp.
        final stamped = '[${DateTime.now().millisecondsSinceEpoch}] $line';
        buffer.writeln(stamped);
        // Call parent.print to actually output the line.
        parent.print(zone, stamped);
      },
    ),
  );

  zone.run(() {
    print('Hello from intercepted zone');
    print('Another line');
  });

  print('Lines captured in buffer: ${buffer.toString().trim().split('\n').length}');
  print('');
}

// ---------------------------------------------------------------------------
// Example 2: Five ways to override scheduleMicrotask
// ---------------------------------------------------------------------------
Future<void> example2_interceptMicrotask() async {
  print('--- Example 2: Five scheduleMicrotask override patterns ---');

  // --- 2a: Wrap — log before and after ---
  await Zone.current.fork(
    specification: ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, fn) {
        parent.print(zone, '  [wrap] scheduling');
        parent.scheduleMicrotask(zone, () {
          parent.print(zone, '  [wrap] running');
          fn();
        });
      },
    ),
  ).run(() async {
    scheduleMicrotask(() => print('  [wrap] microtask body'));
    await Future.delayed(Duration.zero);
  });

  // --- 2b: Delay — defer into a timer instead of the microtask queue ---
  await Zone.current.fork(
    specification: ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, fn) {
        // Runs after a short timer rather than immediately.
        parent.createTimer(zone, const Duration(milliseconds: 5), fn);
      },
    ),
  ).run(() async {
    scheduleMicrotask(() => print('  [delay] ran after timer'));
    await Future.delayed(const Duration(milliseconds: 10));
  });

  // --- 2c: Drop — suppress execution (mirrors fake_async test technique) ---
  final dropped = <String>[];
  Zone.current.fork(
    specification: ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, fn) {
        dropped.add('suppressed');
        // fn is never called.
      },
    ),
  ).run(() {
    scheduleMicrotask(() => print('  [drop] should NOT appear'));
  });
  await Future.delayed(Duration.zero);
  print('  [drop] microtasks suppressed: ${dropped.length}');

  // --- 2d: Run synchronously — execute immediately instead of queuing ---
  print('  [sync] before scheduleMicrotask');
  Zone.current.fork(
    specification: ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, fn) {
        fn(); // runs now, inline
      },
    ),
  ).run(() {
    scheduleMicrotask(() => print('  [sync] ran inline, not queued'));
  });
  print('  [sync] after scheduleMicrotask');

  // --- 2e: Redirect — run in a different zone (e.g. Zone.root) ---
  // fn is already zone-bound to the child, so wrap it in a fresh closure
  // registered by Zone.root — that wrapper runs in root, then calls fn().
  Zone? microtaskZone;
  Zone.current.fork().fork(
    specification: ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, fn) {
        Zone.root.scheduleMicrotask(() {
          microtaskZone = Zone.current; // captured while running in root
          fn();
        });
      },
    ),
  ).run(() {
    scheduleMicrotask(() {});
  });
  await Future.delayed(Duration.zero);
  print('  [redirect] wrapper ran in root? ${microtaskZone == Zone.root}');

  print('');
}

// ---------------------------------------------------------------------------
// Example 3: Intercepting timer creation
// ---------------------------------------------------------------------------
Future<void> example3_interceptTimer() async {
  print('--- Example 3: Intercepting createTimer ---');

  final timerLog = <String>[];

  final zone = Zone.current.fork(
    specification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        timerLog.add('one-shot timer: ${duration.inMilliseconds}ms');
        // Wrap the callback to log when it fires.
        return parent.createTimer(zone, duration, () {
          timerLog.add('one-shot fired after ${duration.inMilliseconds}ms');
          callback();
        });
      },
      createPeriodicTimer: (self, parent, zone, period, callback) {
        timerLog.add('periodic timer: ${period.inMilliseconds}ms interval');
        int ticks = 0;
        return parent.createPeriodicTimer(zone, period, (timer) {
          ticks++;
          timerLog.add('periodic tick #$ticks');
          callback(timer);
        });
      },
    ),
  );

  await zone.run(() async {
    Timer(const Duration(milliseconds: 5), () {});
    final periodic = Timer.periodic(const Duration(milliseconds: 3), (t) {
      if (t.tick >= 2) t.cancel();
    });
    await Future.delayed(const Duration(milliseconds: 20));
    periodic.cancel();
  });

  for (final entry in timerLog) {
    print(entry);
  }
  print('');
}

// ---------------------------------------------------------------------------
// Example 4: Intercepting registerCallback
//
// registerCallback is called whenever a closure is stored to be invoked
// later (e.g., by a Future or Stream). Intercepting it lets you wrap
// every async callback — useful for profiling or context propagation.
// ---------------------------------------------------------------------------
Future<void> example4_registerCallback() async {
  print('--- Example 4: registerCallback ---');

  int wrapCount = 0;

  final zone = Zone.current.fork(
    specification: ZoneSpecification(
      registerCallback: <R>(self, parent, zone, f) {
        wrapCount++;
        // Return a wrapped version of f.
        return parent.registerCallback(zone, () {
          // Could set up context here before calling f.
          return f();
        });
      },
      registerUnaryCallback: <R, T>(self, parent, zone, f) {
        wrapCount++;
        return parent.registerUnaryCallback(zone, (T arg) {
          return f(arg);
        });
      },
    ),
  );

  await zone.run(() async {
    await Future.value(1).then((v) => v + 1);
    await Future.value('hello');
  });

  print('Callbacks wrapped: $wrapCount');
  print('');
}

// ---------------------------------------------------------------------------
// Example 5: Combining multiple interceptors — structured zone spec
// ---------------------------------------------------------------------------
Future<void> example5_combined() async {
  print('--- Example 5: Combined interceptors ---');

  final log = <String>[];

  ZoneSpecification buildSpec({required String label}) {
    return ZoneSpecification(
      print: (self, parent, zone, line) {
        log.add('$label PRINT: $line');
        parent.print(zone, '$label | $line');
      },
      handleUncaughtError: (self, parent, zone, error, stack) {
        log.add('$label ERROR: $error');
        // Don't propagate — we handled it.
      },
      scheduleMicrotask: (self, parent, zone, f) {
        log.add('$label MICRO');
        parent.scheduleMicrotask(zone, f);
      },
    );
  }

  await Zone.current
      .fork(specification: buildSpec(label: 'A'))
      .run(() async {
        print('message from A');
        scheduleMicrotask(() {});
        Future.error(Exception('oops from A'));
        await Future.delayed(const Duration(milliseconds: 5));
      });

  print('\nEvent log:');
  for (final entry in log) {
    print('  $entry');
  }
  print('');
}
