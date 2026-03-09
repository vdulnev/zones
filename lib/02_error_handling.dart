/// Lesson 02 — Error Handling with runZonedGuarded
///
/// Topics:
///   - Why uncaught async errors crash the program
///   - runZonedGuarded as a "try/catch for async code"
///   - Error propagation up the zone tree
///   - Rethrowing and swallowing errors
///   - Practical: top-level error logger
///
/// Run: dart run lib/02_error_handling.dart

import 'dart:async';

void main() async {
  print('=== Lesson 02: Error Handling ===\n');

  await example1_problemWithAsyncErrors();
  await example2_runZonedGuarded();
  await example3_errorPropagation();
  await example4_swallowVsRethrow();
  await example5_topLevelErrorLogger();
}

// ---------------------------------------------------------------------------
// Example 1: The problem — async errors escape try/catch
// ---------------------------------------------------------------------------
Future<void> example1_problemWithAsyncErrors() async {
  print('--- Example 1: async errors escape try/catch ---');

  // This catches the error because we await the future.
  try {
    await Future.error(StateError('sync-style async error'));
  } catch (e) {
    print('Caught with try/catch: $e');
  }

  // But "fire and forget" futures are NOT caught by try/catch.
  // Uncomment the line below and it crashes the isolate:
  //   Future.error(StateError('uncaught!'));  // <-- would crash

  print('');
}

// ---------------------------------------------------------------------------
// Example 2: runZonedGuarded catches all unhandled errors in the zone
// ---------------------------------------------------------------------------
Future<void> example2_runZonedGuarded() async {
  print('--- Example 2: runZonedGuarded ---');

  final errors = <Object>[];

  await runZonedGuarded(
    () async {
      // Deliberately throw an unhandled async error.
      Future.error(ArgumentError('fire-and-forget error'));

      // Also a synchronous throw inside async code.
      Future(() => throw StateError('future body throw'));

      // Give futures a chance to complete.
      await Future.delayed(const Duration(milliseconds: 10));
    },
    (error, stackTrace) {
      // This is the "onError" handler — replaces the isolate crash.
      errors.add(error);
      print('Zone caught: ${error.runtimeType} — $error');
    },
  );

  print('Total errors captured: ${errors.length}');
  print('');
}

// ---------------------------------------------------------------------------
// Example 3: Error propagation — child errors bubble to parent zone
// ---------------------------------------------------------------------------
Future<void> example3_errorPropagation() async {
  print('--- Example 3: Error propagation ---');

  final log = <String>[];

  // Outer zone: logs all errors it receives.
  await runZonedGuarded(
    () async {
      // Inner zone: handles some errors, lets others propagate.
      runZonedGuarded(
        () {
          // This error is handled by the inner zone handler.
          throw FormatException('handled in inner zone');
        },
        (error, stack) {
          if (error is FormatException) {
            log.add('inner handled: $error');
            // Swallow it — do NOT rethrow. Propagation stops here.
          } else {
            // Rethrow by re-throwing inside a new Future so it propagates.
            Zone.current.parent!.handleUncaughtError(error, stack);
          }
        },
      );

      // This error comes from outside the inner zone.
      Future.error(TypeError());
      await Future.delayed(const Duration(milliseconds: 10));
    },
    (error, stack) {
      log.add('outer handled: ${error.runtimeType}');
    },
  );

  for (final entry in log) {
    print(entry);
  }
  print('');
}

// ---------------------------------------------------------------------------
// Example 4: Swallowing vs rethrowing an error
// ---------------------------------------------------------------------------
Future<void> example4_swallowVsRethrow() async {
  print('--- Example 4: Swallow vs rethrow ---');

  // Swallow — error is silently consumed.
  runZonedGuarded(
    () => Future.error('swallowed'),
    (e, s) => print('Swallowed: $e (not propagated)'),
  );

  // Forward to parent: capture Zone.current INSIDE the outer runZonedGuarded
  // body — that IS the zone with the error handler. Re-throw there so the
  // outer handler picks it up.
  final parentErrors = <Object>[];

  await runZonedGuarded(
    () async {
      // Zone.current here is the zone created by the outer runZonedGuarded.
      final outerZone = Zone.current;

      runZonedGuarded(
        () {
          Future.error(FormatException('inner handles this'));
          Future.error(StateError('forwarded to outer'));
        },
        (error, stack) {
          if (error is FormatException) {
            print('Inner handled: $error');
          } else {
            // Re-schedule in the outer zone so outer handler catches it.
            outerZone.run(() => Future.error(error));
          }
        },
      );

      await Future.delayed(const Duration(milliseconds: 10));
    },
    (error, stack) {
      parentErrors.add(error);
      print('Outer received forwarded error: ${error.runtimeType} — $error');
    },
  );

  assert(parentErrors.length == 1 && parentErrors.first is StateError);
  print('');
}

// ---------------------------------------------------------------------------
// Example 5: Practical — top-level error logger
// ---------------------------------------------------------------------------
Future<void> example5_topLevelErrorLogger() async {
  print('--- Example 5: Top-level error logger ---');

  final List<String> errorLog = [];

  void logError(Object error, StackTrace stack) {
    final message = '[ERROR] ${DateTime.now().toIso8601String()} '
        '${error.runtimeType}: $error';
    errorLog.add(message);
    print(message);
    // In production: send to Sentry, Firebase Crashlytics, etc.
  }

  // Wrap your entire app logic in runZonedGuarded so every uncaught
  // error is routed to logError instead of crashing the process.
  await runZonedGuarded(
    () async {
      print('App starting…');

      // Simulate several async tasks that may fail.
      Future.delayed(const Duration(milliseconds: 5),
          () => throw StateError('background task failed'));

      Future.delayed(const Duration(milliseconds: 8),
          () => throw ArgumentError('invalid config value'));

      // Main work succeeds.
      await Future.delayed(const Duration(milliseconds: 20));
      print('App finished normally.');
    },
    logError,
  );

  print('Errors logged: ${errorLog.length}');
  print('');
}
