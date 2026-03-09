/// Lesson 07 — Flutter Integration and Global Error Handling
///
/// Topics:
///   - Where Flutter uses zones internally
///   - Wrapping runApp in runZonedGuarded
///   - FlutterError.onError vs zone error handler — and why you need both
///   - Reporting errors to Sentry / Firebase Crashlytics
///   - Zone-based request-ID propagation in Navigator/Router
///   - WidgetBinding zones (brief overview)
///
/// IMPORTANT: This file contains Flutter code — it will NOT run with
///   `dart run`. It is meant to be read and copied into a Flutter project.
///   The patterns are annotated with explanations inline.
///
/// Quick reference for a Flutter main.dart:
///
///   void main() {
///     runZonedGuarded(
///       () async {
///         WidgetsFlutterBinding.ensureInitialized();
///         FlutterError.onError = (details) {
///           FlutterError.presentError(details); // dev: show red screen
///           myErrorReporter.report(details.exception, details.stack!);
///         };
///         runApp(const MyApp());
///       },
///       (error, stack) => myErrorReporter.report(error, stack),
///     );
///   }

// ignore_for_file: unused_import, prefer_const_constructors

/// ---------------------------------------------------------------------------
/// PATTERN 1: The "golden" Flutter main.dart setup
/// ---------------------------------------------------------------------------
///
/// ```dart
/// import 'dart:async';
/// import 'package:flutter/foundation.dart';
/// import 'package:flutter/material.dart';
///
/// // Stand-in for Sentry, Crashlytics, Datadog, etc.
/// abstract class ErrorReporter {
///   static void report(Object error, StackTrace stack) {
///     // In production: Sentry.captureException(error, stackTrace: stack);
///     debugPrint('ERROR: $error\n$stack');
///   }
/// }
///
/// void main() {
///   // runZonedGuarded catches errors that escape Flutter's own error handler.
///   // These include errors thrown in Timer callbacks, Isolate.spawn, etc.
///   runZonedGuarded(
///     () async {
///       WidgetsFlutterBinding.ensureInitialized();
///
///       // Flutter's widget-level error handler (e.g. build exceptions).
///       FlutterError.onError = (FlutterErrorDetails details) {
///         // In debug mode, Flutter renders a red error screen.
///         FlutterError.presentError(details);
///         // In release mode, send to crash reporter.
///         if (!kDebugMode) {
///           ErrorReporter.report(details.exception, details.stack!);
///         }
///       };
///
///       // PlatformDispatcher catches errors from native-to-dart callbacks.
///       PlatformDispatcher.instance.onError = (error, stack) {
///         ErrorReporter.report(error, stack);
///         return true; // mark as handled
///       };
///
///       runApp(const MyApp());
///     },
///     // Zone handler: catches everything else.
///     (error, stack) => ErrorReporter.report(error, stack),
///   );
/// }
/// ```

/// ---------------------------------------------------------------------------
/// PATTERN 2: Why three error handlers?
/// ---------------------------------------------------------------------------
///
/// Flutter has three layers of async error handling:
///
/// ┌─────────────────────────────────────────────────────────┐
/// │  Zone (runZonedGuarded)                                  │
/// │   ┌─────────────────────────────────────────────────┐   │
/// │   │  PlatformDispatcher.onError                      │   │
/// │   │   ┌─────────────────────────────────────────┐   │   │
/// │   │   │  FlutterError.onError                    │   │   │
/// │   │   │  (widget build / layout / paint errors)  │   │   │
/// │   │   └─────────────────────────────────────────┘   │   │
/// │   └─────────────────────────────────────────────────┘   │
/// └─────────────────────────────────────────────────────────┘
///
/// - FlutterError.onError  — build errors, assertion failures in widgets
/// - PlatformDispatcher    — isolate errors, platform channel errors
/// - Zone                  — Timer callbacks, raw async errors, everything else
///
/// You need all three to achieve 100% coverage.

/// ---------------------------------------------------------------------------
/// PATTERN 3: Request-ID propagation in a GoRouter/Navigator app
/// ---------------------------------------------------------------------------
///
/// ```dart
/// final _requestIdKey = Object();
///
/// // Retrieve the current request ID from the zone (any code, any depth).
/// String get currentRequestId =>
///     Zone.current[_requestIdKey] as String? ?? 'no-request';
///
/// // Middleware-style wrapper: gives every navigation action an ID.
/// Future<T> withRequestId<T>(String id, Future<T> Function() action) =>
///     Zone.current
///         .fork(zoneValues: {_requestIdKey: id})
///         .run(action);
///
/// // In a feature's business logic:
/// Future<void> loadProfile() async {
///   final id = currentRequestId; // available without passing it as argument
///   log('[$id] Loading profile…');
///   final user = await api.fetchUser();
///   log('[$id] Profile loaded: ${user.name}');
/// }
/// ```

/// ---------------------------------------------------------------------------
/// PATTERN 4: Zone-based feature flags (read-only, scope-limited)
/// ---------------------------------------------------------------------------
///
/// ```dart
/// final _featureFlagsKey = Object();
///
/// class FeatureFlags {
///   final bool newCheckoutFlow;
///   final bool darkModeEnabled;
///   const FeatureFlags({
///     required this.newCheckoutFlow,
///     required this.darkModeEnabled,
///   });
/// }
///
/// FeatureFlags get flags =>
///     Zone.current[_featureFlagsKey] as FeatureFlags? ??
///     const FeatureFlags(newCheckoutFlow: false, darkModeEnabled: false);
///
/// // In tests, inject overrides without touching production code:
/// testWidgets('new checkout flow', (tester) async {
///   await Zone.current.fork(zoneValues: {
///     _featureFlagsKey: const FeatureFlags(
///       newCheckoutFlow: true,
///       darkModeEnabled: false,
///     ),
///   }).run(() => tester.pumpWidget(const MyApp()));
///
///   // The widget tree under test automatically sees newCheckoutFlow=true.
///   expect(find.text('New Checkout'), findsOneWidget);
/// });
/// ```

/// ---------------------------------------------------------------------------
/// PATTERN 5: Capturing all logs in widget tests
/// ---------------------------------------------------------------------------
///
/// ```dart
/// Future<void> pumpWithLogCapture(
///   WidgetTester tester,
///   Widget widget, {
///   required List<String> logOutput,
/// }) async {
///   await Zone.current.fork(
///     specification: ZoneSpecification(
///       print: (self, parent, zone, line) => logOutput.add(line),
///     ),
///   ).run(() => tester.pumpWidget(widget));
/// }
///
/// testWidgets('logs on tap', (tester) async {
///   final logs = <String>[];
///   await pumpWithLogCapture(tester, const MyButton(), logOutput: logs);
///   await tester.tap(find.byType(MyButton));
///   await tester.pump();
///   expect(logs, contains('button tapped'));
/// });
/// ```

/// ---------------------------------------------------------------------------
/// PATTERN 6: Zone-local state for dependency injection in tests
/// ---------------------------------------------------------------------------
///
/// This is how packages like `package:get_it` can be scoped per test:
///
/// ```dart
/// final _containerKey = Object();
///
/// // Type-safe accessor.
/// T get<T>() {
///   final container = Zone.current[_containerKey] as Map<Type, Object>?;
///   return container?[T] as T? ?? _globalContainer[T] as T;
/// }
///
/// Future<void> withDependencies(
///   Map<Type, Object> overrides,
///   Future<void> Function() body,
/// ) =>
///   Zone.current
///     .fork(zoneValues: {_containerKey: overrides})
///     .run(body);
///
/// // In tests:
/// await withDependencies({
///   ApiClient: MockApiClient(),
///   AuthService: FakeAuthService(),
/// }, () async {
///   final viewModel = ProfileViewModel();
///   await viewModel.load();
///   expect(viewModel.user.name, 'Test User');
/// });
/// ```

void main() {
  // This file is documentation — see the patterns above.
  print('Lesson 07 is a reference file. '
      'Copy the patterns into your Flutter project.');
  print('');
  print('Key takeaways:');
  print('1. Wrap runApp in runZonedGuarded for catch-all error handling.');
  print('2. Set FlutterError.onError AND PlatformDispatcher.onError too.');
  print('3. Use zone values to propagate request IDs, feature flags, DI.');
  print('4. Intercept print in tests to capture widget log output cleanly.');
}
