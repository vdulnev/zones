# Dart Zones — Learning Course

A hands-on course covering Dart's Zone system from basics to advanced use cases.

## What Are Zones?

Zones are execution contexts in Dart that persist across asynchronous boundaries. Every piece of
Dart code runs inside a zone. They let you intercept and customize asynchronous behavior:
error handling, print output, timers, microtasks, and more — all without modifying the original code.

## Course Structure

| Lesson | Topic | File |
|--------|-------|------|
| 01 | Zone basics, hierarchy, and `Zone.current` | [lib/01_basics.dart](lib/01_basics.dart) |
| 02 | Error handling with `runZonedGuarded` | [lib/02_error_handling.dart](lib/02_error_handling.dart) |
| 03 | Zone values — scoped state across async code | [lib/03_zone_values.dart](lib/03_zone_values.dart) |
| 04 | Intercepting callbacks: print, timers, microtasks | [lib/04_callbacks.dart](lib/04_callbacks.dart) |
| 05 | Async tracking and performance monitoring | [lib/05_async_tracking.dart](lib/05_async_tracking.dart) |
| 06 | Testing with zones (fake timers, error capture) | [lib/06_testing.dart](lib/06_testing.dart) |
| 07 | Flutter integration and global error handling | [lib/07_flutter_integration.dart](lib/07_flutter_integration.dart) |

## Running the Examples

```bash
# Run individual lessons
dart run lib/01_basics.dart
dart run lib/02_error_handling.dart
# ... etc.
```

## Key Concepts at a Glance

```
Root zone (always exists)
  └── Custom zone (fork of root)
        └── Child zone (fork of parent)
              └── ...
```

- **Zone.root** — the top-level zone that Dart creates at startup
- **Zone.current** — the zone currently executing code
- **zone.fork()** — creates a child zone with optional overrides
- **zone.run()** — executes a callback inside that zone
- **runZonedGuarded()** — convenience wrapper for error-catching zones
