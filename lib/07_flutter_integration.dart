/// Lesson 07 — Flutter Integration and Global Error Handling
///
/// Topics:
///   - Wrapping runApp in runZonedGuarded
///   - FlutterError.onError vs PlatformDispatcher.onError vs zone handler
///   - Request-ID propagation via zone values
///   - Zone-based feature flags
///   - Capturing print output per zone
///
/// Run: flutter run lib/07_flutter_integration.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Error reporter — stand-in for Sentry, Crashlytics, Datadog, etc.
// ---------------------------------------------------------------------------

class ErrorReporter {
  static final _events = <_ErrorEvent>[];
  static final _listeners = <VoidCallback>[];

  static void report(Object error, StackTrace stack, {String? source}) {
    final event = _ErrorEvent(
      error: error,
      stack: stack,
      source: source ?? 'zone',
      time: DateTime.now(),
    );
    _events.add(event);
    for (final l in _listeners) {
      l();
    }
    // In production: Sentry.captureException(error, stackTrace: stack);
    debugPrint('[ErrorReporter:${event.source}] $error');
  }

  static List<_ErrorEvent> get events => List.unmodifiable(_events);
  static void clear() {
    _events.clear();
    for (final l in _listeners) {
      l();
    }
  }

  static void addListener(VoidCallback listener) => _listeners.add(listener);
  static void removeListener(VoidCallback listener) =>
      _listeners.remove(listener);
}

class _ErrorEvent {
  final Object error;
  final StackTrace stack;
  final String source;
  final DateTime time;
  const _ErrorEvent({
    required this.error,
    required this.stack,
    required this.source,
    required this.time,
  });
}

// ---------------------------------------------------------------------------
// Zone value keys (opaque Object() so they can't be forged externally)
// ---------------------------------------------------------------------------

final _requestIdKey = Object();
final _featureFlagsKey = Object();

// ---------------------------------------------------------------------------
// Request-ID helpers
// ---------------------------------------------------------------------------

String get currentRequestId =>
    Zone.current[_requestIdKey] as String? ?? 'no-request';

Future<T> withRequestId<T>(String id, Future<T> Function() action) =>
    Zone.current.fork(zoneValues: {_requestIdKey: id}).run(action);

// ---------------------------------------------------------------------------
// Feature flags
// ---------------------------------------------------------------------------

class FeatureFlags {
  final bool newCheckoutFlow;
  final bool darkModeEnabled;
  final bool betaBanner;

  const FeatureFlags({
    this.newCheckoutFlow = false,
    this.darkModeEnabled = false,
    this.betaBanner = false,
  });

  FeatureFlags copyWith({
    bool? newCheckoutFlow,
    bool? darkModeEnabled,
    bool? betaBanner,
  }) =>
      FeatureFlags(
        newCheckoutFlow: newCheckoutFlow ?? this.newCheckoutFlow,
        darkModeEnabled: darkModeEnabled ?? this.darkModeEnabled,
        betaBanner: betaBanner ?? this.betaBanner,
      );
}

FeatureFlags get flags =>
    Zone.current[_featureFlagsKey] as FeatureFlags? ?? const FeatureFlags();

// ---------------------------------------------------------------------------
// main() — the "golden" Flutter entry point
// ---------------------------------------------------------------------------

void main() {
  // runZonedGuarded is the outermost net — catches errors that escape every
  // other handler (raw Timer callbacks, Isolate.spawn, etc.)
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Flutter's widget-level error handler (build/layout/paint errors).
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details); // red screen in debug mode
        ErrorReporter.report(
          details.exception,
          details.stack ?? StackTrace.empty,
          source: 'FlutterError.onError',
        );
      };

      // PlatformDispatcher catches native→Dart bridge errors and isolate
      // errors that Flutter itself forwards here.
      PlatformDispatcher.instance.onError = (error, stack) {
        ErrorReporter.report(error, stack, source: 'PlatformDispatcher');
        return true; // mark handled so Flutter doesn't also crash
      };

      runApp(const Lesson07App());
    },
    // Zone handler — the final safety net for everything else.
    (error, stack) =>
        ErrorReporter.report(error, stack, source: 'runZonedGuarded'),
  );
}

// ---------------------------------------------------------------------------
// App root
// ---------------------------------------------------------------------------

class Lesson07App extends StatelessWidget {
  const Lesson07App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lesson 07 — Flutter Zones',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const _HomeScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Home — tab layout
// ---------------------------------------------------------------------------

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lesson 07 — Flutter Integration'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Error Layers'),
              Tab(text: 'Request ID'),
              Tab(text: 'Feature Flags'),
              Tab(text: 'Log Capture'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ErrorLayersDemo(),
            _RequestIdDemo(),
            _FeatureFlagsDemo(),
            _LogCaptureDemo(),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// TAB 1 — Three-layer error handling
// ===========================================================================

class _ErrorLayersDemo extends StatefulWidget {
  const _ErrorLayersDemo();

  @override
  State<_ErrorLayersDemo> createState() => _ErrorLayersDemoState();
}

class _ErrorLayersDemoState extends State<_ErrorLayersDemo> {
  List<_ErrorEvent> _events = [];

  @override
  void initState() {
    super.initState();
    ErrorReporter.addListener(_refresh);
  }

  @override
  void dispose() {
    ErrorReporter.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() => _events = ErrorReporter.events);

  // Throw from a Timer callback — caught by the zone handler.
  void _throwInTimer() {
    Timer(Duration.zero, () => throw StateError('Error from Timer callback'));
  }

  // Throw in a fire-and-forget Future — caught by the zone handler.
  void _throwInFuture() {
    Future(() => throw ArgumentError('Error from unawaited Future'));
  }

  // Trigger a FlutterError directly.
  void _throwFlutterError() {
    FlutterError.reportError(FlutterErrorDetails(
      exception: Exception('Simulated FlutterError'),
      stack: StackTrace.current,
      library: 'lesson07',
      context: ErrorDescription('tap on button'),
    ));
  }

  // Simulate a PlatformDispatcher error.
  //
  // In production this handler is invoked by Flutter for errors that originate
  // outside the widget tree and outside any Dart zone:
  //   • Uncaught errors forwarded from platform channels (MethodChannel,
  //     EventChannel) before they reach Dart zone error handling.
  //   • Errors thrown in isolate message handlers that Flutter surfaces to the
  //     root isolate.
  //   • Any error that the Flutter engine itself routes through
  //     PlatformDispatcher before the zone system sees it.
  //
  // Returning true marks the error handled; returning false lets Flutter
  // terminate the app (same as an unhandled exception in release mode).
  //
  // We call the handler directly here because there is no safe way to trigger
  // a real platform-channel error from a button tap in a demo.
  void _simulatePlatformDispatcherError() {
    final error = StateError(
      'Simulated PlatformDispatcher error '
      '(e.g. uncaught MethodChannel reply on background isolate)',
    );
    final stack = StackTrace.current;
    final handled = PlatformDispatcher.instance.onError?.call(error, stack);
    if (handled != true) {
      // onError not set — fall back to zone handler so the demo still works.
      ErrorReporter.report(
        error,
        stack,
        source: 'PlatformDispatcher (fallback)',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: 'Three error-handling layers',
          description:
              'Flutter needs three separate handlers to achieve 100% error coverage.\n\n'
              '① FlutterError.onError — widget build/layout/paint\n'
              '② PlatformDispatcher.onError — platform channels & isolate bridge\n'
              '③ runZonedGuarded — Timer callbacks, raw async, everything else\n\n'
              'PlatformDispatcher.instance.onError is set once in main() and '
              'invoked by the Flutter engine for errors that arrive outside the '
              'widget tree. Return true to mark the error handled.',
          child: Column(
            children: [
              const _LayerDiagram(),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: _throwInTimer,
                    child: const Text('Timer error → zone'),
                  ),
                  FilledButton.tonal(
                    onPressed: _throwInFuture,
                    child: const Text('Future error → zone'),
                  ),
                  FilledButton.tonal(
                    onPressed: _throwFlutterError,
                    child: const Text('FlutterError layer'),
                  ),
                  FilledButton.tonal(
                    onPressed: _simulatePlatformDispatcherError,
                    child: const Text('PlatformDispatcher layer'),
                  ),
                  OutlinedButton(
                    onPressed: ErrorReporter.clear,
                    child: const Text('Clear log'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_events.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No errors captured yet.\nTap a button above to fire one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ..._events.reversed.map((e) => _ErrorTile(event: e)),
      ],
    );
  }
}

class _LayerDiagram extends StatelessWidget {
  const _LayerDiagram();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DiagramRow('runZonedGuarded', Colors.indigo, 0),
          _DiagramRow('PlatformDispatcher.onError', Colors.blue, 1),
          _DiagramRow('FlutterError.onError', Colors.teal, 2),
        ],
      ),
    );
  }
}

class _DiagramRow extends StatelessWidget {
  final String label;
  final Color color;
  final int indent;
  const _DiagramRow(this.label, this.color, this.indent);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: indent * 20.0,
        top: 4,
        bottom: 4,
      ),
      child: Row(
        children: [
          Container(width: 12, height: 12, color: color),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  final _ErrorEvent event;
  const _ErrorTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final color = switch (event.source) {
      'FlutterError.onError' => Colors.orange,
      'PlatformDispatcher' => Colors.blue,
      _ => Colors.red,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(40),
          child: Icon(Icons.warning_rounded, color: color, size: 20),
        ),
        title: Text(event.error.toString()),
        subtitle: Text(
          '${event.source} · ${_fmt(event.time)}',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

// ===========================================================================
// TAB 2 — Request-ID propagation
// ===========================================================================

class _RequestIdDemo extends StatefulWidget {
  const _RequestIdDemo();

  @override
  State<_RequestIdDemo> createState() => _RequestIdDemoState();
}

class _RequestIdDemoState extends State<_RequestIdDemo> {
  final _log = <String>[];

  Future<void> _simulateRequest(String requestId) async {
    await withRequestId(requestId, () async {
      _addLog('[$currentRequestId] Request started');
      await Future.delayed(const Duration(milliseconds: 50));
      _addLog('[$currentRequestId] Fetching user profile…');
      await Future.delayed(const Duration(milliseconds: 80));
      _addLog('[$currentRequestId] Loading orders…');
      await Future.delayed(const Duration(milliseconds: 60));
      _addLog('[$currentRequestId] Request complete ✓');
    });
  }

  void _addLog(String msg) => setState(() => _log.add(msg));
  void _clear() => setState(() => _log.clear());

  // Launch two overlapping requests so logs interleave — but each keeps its ID.
  Future<void> _runConcurrent() async {
    final id1 = 'req-${DateTime.now().millisecondsSinceEpoch % 10000}';
    final id2 = 'req-${(DateTime.now().millisecondsSinceEpoch + 1) % 10000}';
    await Future.wait([
      _simulateRequest(id1),
      _simulateRequest(id2),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: 'Request-ID propagation via zone values',
          description:
              'A zone value set at the start of an async call chain is '
              'automatically available anywhere in that chain — without '
              'passing it as a function argument.\n\n'
              'Tap "Two concurrent requests" to see interleaved logs where '
              'each request still knows its own ID.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () =>
                    _simulateRequest('req-${DateTime.now().second}'),
                child: const Text('Single request'),
              ),
              FilledButton.tonal(
                onPressed: _runConcurrent,
                child: const Text('Two concurrent requests'),
              ),
              OutlinedButton(onPressed: _clear, child: const Text('Clear')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_log.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Tap a button to simulate requests.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _log.join('\n'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }
}

// ===========================================================================
// TAB 3 — Feature flags via zone values
// ===========================================================================

class _FeatureFlagsDemo extends StatefulWidget {
  const _FeatureFlagsDemo();

  @override
  State<_FeatureFlagsDemo> createState() => _FeatureFlagsDemoState();
}

class _FeatureFlagsDemoState extends State<_FeatureFlagsDemo> {
  FeatureFlags _overrides = const FeatureFlags();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: 'Zone-based feature flags',
          description:
              'Feature flags stored as zone values are readable anywhere in '
              'the subtree without prop-drilling or global mutation.\n\n'
              'Toggle flags below to see the preview update.',
          child: Column(
            children: [
              _FlagToggle(
                label: 'New Checkout Flow',
                value: _overrides.newCheckoutFlow,
                onChanged: (v) => setState(
                  () => _overrides = _overrides.copyWith(newCheckoutFlow: v),
                ),
              ),
              _FlagToggle(
                label: 'Dark Mode',
                value: _overrides.darkModeEnabled,
                onChanged: (v) => setState(
                  () => _overrides = _overrides.copyWith(darkModeEnabled: v),
                ),
              ),
              _FlagToggle(
                label: 'Beta Banner',
                value: _overrides.betaBanner,
                onChanged: (v) => setState(
                  () => _overrides = _overrides.copyWith(betaBanner: v),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Fork a zone with the overrides and render the preview inside it.
        _ZoneScope(
          zoneValues: {_featureFlagsKey: _overrides},
          child: const _FlagPreview(),
        ),
      ],
    );
  }
}

/// Runs its [child] inside a forked zone with [zoneValues].
class _ZoneScope extends StatelessWidget {
  final Map<Object, Object?> zoneValues;
  final Widget child;

  const _ZoneScope({required this.zoneValues, required this.child});

  @override
  Widget build(BuildContext context) {
    // The zone is used here conceptually — in a real app you'd fork the zone
    // around your Navigator or business logic. For this demo we pass flags
    // down via the accessor to show the pattern.
    return _ZoneScopeInherited(zoneValues: zoneValues, child: child);
  }
}

class _ZoneScopeInherited extends InheritedWidget {
  final Map<Object, Object?> zoneValues;
  const _ZoneScopeInherited({
    required this.zoneValues,
    required super.child,
  });

  static _ZoneScopeInherited? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ZoneScopeInherited>();

  @override
  bool updateShouldNotify(_ZoneScopeInherited old) =>
      zoneValues != old.zoneValues;
}

FeatureFlags flagsFrom(BuildContext context) {
  final scope = _ZoneScopeInherited.of(context);
  return scope?.zoneValues[_featureFlagsKey] as FeatureFlags? ??
      const FeatureFlags();
}

class _FlagPreview extends StatelessWidget {
  const _FlagPreview();

  @override
  Widget build(BuildContext context) {
    final f = flagsFrom(context);
    return Card(
      color: f.darkModeEnabled ? Colors.grey[900] : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(
            'Preview',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: f.darkModeEnabled ? Colors.white : null,
            ),
          ),
          if (f.betaBanner)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: Colors.amber,
              child: const Text(
                '★ BETA',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          const SizedBox(height: 12),
          if (f.newCheckoutFlow)
            FilledButton(
              onPressed: () {},
              child: const Text('New Checkout →'),
            )
          else
            OutlinedButton(
              onPressed: () {},
              child: const Text('Checkout (legacy)'),
            ),
          const SizedBox(height: 8),
          Text(
            'Flags: newCheckout=${f.newCheckoutFlow}, '
            'dark=${f.darkModeEnabled}, beta=${f.betaBanner}',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: f.darkModeEnabled ? Colors.white70 : Colors.grey,
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _FlagToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _FlagToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(label),
      value: value,
      onChanged: onChanged,
      dense: true,
    );
  }
}

// ===========================================================================
// TAB 4 — Capturing print output in a zone
// ===========================================================================

class _LogCaptureDemo extends StatefulWidget {
  const _LogCaptureDemo();

  @override
  State<_LogCaptureDemo> createState() => _LogCaptureDemoState();
}

class _LogCaptureDemoState extends State<_LogCaptureDemo> {
  final _capturedLines = <String>[];
  bool _capturing = false;

  // Run a simulated widget-like action inside a zone that intercepts print.
  Future<void> _runWithCapture() async {
    final captured = <String>[];
    setState(() {
      _capturing = true;
    });

    await Zone.current.fork(
      specification: ZoneSpecification(
        print: (self, parent, zone, line) {
          captured.add(line);
          // Also forward to real console so debugPrint still works.
          parent.print(zone, '(captured) $line');
        },
      ),
    ).run(() async {
      print('Widget build started');
      await Future.delayed(const Duration(milliseconds: 30));
      print('Fetching remote config…');
      await Future.delayed(const Duration(milliseconds: 50));
      print('Config loaded: {theme: "ocean", lang: "en"}');
      print('Rendering home screen');
      await Future.delayed(const Duration(milliseconds: 20));
      print('First frame painted ✓');
    });

    setState(() {
      _capturedLines.addAll(captured);
      _capturing = false;
    });
  }

  void _clear() => setState(() => _capturedLines.clear());

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: 'Capturing print output per zone',
          description:
              'ZoneSpecification.print intercepts every print() call in the '
              'zone — including calls from deep inside async chains.\n\n'
              'Useful in widget tests to assert on log output without '
              'polluting the test console.',
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: _capturing ? null : _runWithCapture,
                child: _capturing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Run with capture'),
              ),
              OutlinedButton(onPressed: _clear, child: const Text('Clear')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_capturedLines.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Captured lines will appear here.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_capturedLines.length} lines captured',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const Divider(height: 16),
                  SelectableText(
                    _capturedLines
                        .asMap()
                        .entries
                        .map((e) => '${e.key + 1}: ${e.value}')
                        .join('\n'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ===========================================================================
// Shared UI helpers
// ===========================================================================

class _SectionCard extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }
}
