/// Lesson 01 — Zone Basics and Hierarchy
///
/// Topics:
///   - Zone.root and Zone.current
///   - Forking a zone
///   - Running code inside a zone
///   - Zone identity across async boundaries
///
/// Run: dart run lib/01_basics.dart

import 'dart:async';

void main() async {
  print('=== Lesson 01: Zone Basics ===\n');

  example1_rootAndCurrent();
  await example2_forkAndRun();
  await example3_identityAcrossAsync();
  example4_nestedZones();
}

// ---------------------------------------------------------------------------
// Example 1: Zone.root vs Zone.current
// ---------------------------------------------------------------------------
void example1_rootAndCurrent() {
  print('--- Example 1: Zone.root vs Zone.current ---');

  // Zone.root is the implicit zone Dart starts with.
  // main() runs inside the root zone by default.
  print('In main: Zone.current == Zone.root? '
      '${Zone.current == Zone.root}'); // true

  Zone.current.fork().run(() {
    // Inside a forked zone, current is no longer root.
    print('In fork: Zone.current == Zone.root? '
        '${Zone.current == Zone.root}'); // false
    print('In fork: Zone.current.parent == Zone.root? '
        '${Zone.current.parent == Zone.root}'); // true
  });

  print('Back in main: Zone.current == Zone.root? '
      '${Zone.current == Zone.root}\n'); // true again
}

// ---------------------------------------------------------------------------
// Example 2: Forking a zone and running code inside it
// ---------------------------------------------------------------------------
Future<void> example2_forkAndRun() async {
  print('--- Example 2: fork() and run() ---');

  // fork() creates a child zone without changing current execution context.
  final child = Zone.current.fork();

  print('Outside child — current is root: ${Zone.current == Zone.root}');

  // run() executes a closure inside the zone synchronously.
  child.run(() {
    print('Inside child.run() — current is child: ${Zone.current == child}');
  });

  // runUnary / runBinary — same but pass 1 or 2 arguments to the closure.
  final result = child.runUnary((int x) => x * 2, 21);
  print('child.runUnary result: $result'); // 42

  // runGuarded wraps run() and routes errors to the zone's error handler.
  child.runGuarded(() => print('child.runGuarded OK'));

  print('');
}

// ---------------------------------------------------------------------------
// Example 3: Zone identity is preserved across async boundaries
// ---------------------------------------------------------------------------
Future<void> example3_identityAcrossAsync() async {
  print('--- Example 3: Identity across async ---');

  Zone? capturedZone;

  final myZone = Zone.current.fork();

  // Schedule async work *inside* the zone — the zone is captured automatically.
  myZone.run(() async {
    capturedZone = Zone.current;
    await Future.delayed(Duration.zero); // yield to event loop
    // After the await, we're still in myZone — not root!
    print('After await — still in myZone? '
        '${Zone.current == capturedZone}'); // true
  });

  // Wait for the scheduled work to finish before proceeding.
  await Future.delayed(const Duration(milliseconds: 10));
  print('');
}

// ---------------------------------------------------------------------------
// Example 4: Nested zones — a tree, not a stack
// ---------------------------------------------------------------------------
void example4_nestedZones() {
  print('--- Example 4: Nested zone hierarchy ---');

  //  root
  //    └── level1
  //          ├── level2a
  //          └── level2b

  final level1 = Zone.root.fork();
  final level2a = level1.fork();
  final level2b = level1.fork();

  void printLineage(Zone z, String name) {
    final ancestors = <String>[];
    Zone? cursor = z.parent;
    int depth = 0;
    while (cursor != null) {
      ancestors.add(cursor == Zone.root ? 'root' : 'ancestor-$depth');
      cursor = cursor.parent;
      depth++;
    }
    print('$name ancestors: ${ancestors.join(' -> ')}');
  }

  level2a.run(() => printLineage(Zone.current, 'level2a'));
  level2b.run(() => printLineage(Zone.current, 'level2b'));

  // Zones are siblings — neither is an ancestor of the other.
  print('level2a.inSameErrorZone(level2b): '
      '${level2a.inSameErrorZone(level2b)}');

  print('');
}
