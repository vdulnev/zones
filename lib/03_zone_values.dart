/// Lesson 03 — Zone Values: Scoped State Across Async Code
///
/// Topics:
///   - Storing values in a zone with zoneValues
///   - Reading values with zone[key]
///   - Shadowing parent values in child zones
///   - Use case: request ID / trace ID propagation
///   - Use case: scoped dependency injection
///
/// Run: dart run lib/03_zone_values.dart

import 'dart:async';

void main() async {
  print('=== Lesson 03: Zone Values ===\n');

  await example1_basicZoneValues();
  await example2_inheritance();
  await example3_shadowing();
  await example4_requestIdPropagation();
  await example5_scopedDI();
}

// ---------------------------------------------------------------------------
// Example 1: Storing and reading zone values
// ---------------------------------------------------------------------------
Future<void> example1_basicZoneValues() async {
  print('--- Example 1: Basic zone values ---');

  // Use any Object as the key — symbols, strings, or (best) private objects.
  const key = #myValue;

  final zone = Zone.current.fork(zoneValues: {key: 'hello from zone'});

  zone.run(() {
    // Access the value via zone[key] on the CURRENT zone.
    print('Value inside zone: ${Zone.current[key]}'); // hello from zone
  });

  // Outside the zone the value is not visible.
  print('Value outside zone: ${Zone.current[key]}'); // null

  print('');
}

// ---------------------------------------------------------------------------
// Example 2: Values are inherited by child zones
// ---------------------------------------------------------------------------
Future<void> example2_inheritance() async {
  print('--- Example 2: Inheritance ---');

  const key = #inherited;

  final parent = Zone.current.fork(zoneValues: {key: 'from parent'});
  final child = parent.fork(); // No zoneValues override.

  parent.run(() => print('Parent sees: ${Zone.current[key]}'));
  // Child inherits from parent.
  child.run(() => print('Child sees: ${Zone.current[key]}'));

  print('');
}

// ---------------------------------------------------------------------------
// Example 3: Shadowing — child overrides parent value
// ---------------------------------------------------------------------------
Future<void> example3_shadowing() async {
  print('--- Example 3: Shadowing ---');

  const key = #color;

  final parent = Zone.current.fork(zoneValues: {key: 'blue'});
  final child = parent.fork(zoneValues: {key: 'red'}); // shadows parent

  parent.run(() => print('Parent: ${Zone.current[key]}')); // blue
  child.run(() => print('Child:  ${Zone.current[key]}')); // red

  // Parent is unaffected.
  parent.run(() => print('Parent after child ran: ${Zone.current[key]}')); // blue

  print('');
}

// ---------------------------------------------------------------------------
// Example 4: Practical — request ID propagation
//
// In a server, you want every log line for a request to include the same
// trace/request ID — even across many async calls.
// ---------------------------------------------------------------------------
final _requestId = Object(); // private key

Future<void> example4_requestIdPropagation() async {
  print('--- Example 4: Request ID propagation ---');

  Future<void> handleRequest(String id) {
    return Zone.current.fork(zoneValues: {_requestId: id}).run(() async {
      await fetchUser();
      await fetchPermissions();
      await saveAuditLog();
    });
  }

  // Two requests run concurrently — each carries its own ID.
  await Future.wait([
    handleRequest('req-001'),
    handleRequest('req-002'),
  ]);

  print('');
}

void logLine(String message) {
  final id = Zone.current[_requestId] ?? 'no-request';
  print('[$id] $message');
}

Future<void> fetchUser() async {
  await Future.delayed(Duration.zero);
  logLine('fetchUser complete');
}

Future<void> fetchPermissions() async {
  await Future.delayed(Duration.zero);
  logLine('fetchPermissions complete');
}

Future<void> saveAuditLog() async {
  await Future.delayed(Duration.zero);
  logLine('saveAuditLog complete');
}

// ---------------------------------------------------------------------------
// Example 5: Scoped dependency injection via zone values
// ---------------------------------------------------------------------------

// Interface and implementations.
abstract class Logger {
  void log(String message);
}

class ConsoleLogger implements Logger {
  @override
  void log(String message) => print('[Console] $message');
}

class SilentLogger implements Logger {
  final List<String> captured = [];
  @override
  void log(String message) => captured.add(message);
}

final _loggerKey = Object();

// Retrieve the current zone's logger (with fallback to console).
Logger get currentLogger =>
    (Zone.current[_loggerKey] as Logger?) ?? ConsoleLogger();

Future<void> doWork() async {
  await Future.delayed(Duration.zero);
  currentLogger.log('step 1');
  await Future.delayed(Duration.zero);
  currentLogger.log('step 2');
}

Future<void> example5_scopedDI() async {
  print('--- Example 5: Scoped DI ---');

  // Production: logs to console.
  await Zone.current
      .fork(zoneValues: {_loggerKey: ConsoleLogger()})
      .run(doWork);

  // Test: logs to in-memory buffer.
  final testLogger = SilentLogger();
  await Zone.current
      .fork(zoneValues: {_loggerKey: testLogger})
      .run(doWork);

  print('Test captured: ${testLogger.captured}');
  print('');
}
