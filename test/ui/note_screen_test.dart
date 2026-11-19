import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_nudge/data/store.dart';
import 'package:obsidian_nudge/ui/note_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.utc(2026, 5, 1, 12);

Future<(Store, Directory)> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store(
    await SharedPreferences.getInstance(),
    MemoryTokenStore(),
  );
  final dir = Directory.systemTemp.createTempSync('note_screen_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  File('${dir.path}/a.md').writeAsStringSync('# Alpha\n\nHello body text');
  return (store, dir);
}

// Home route pushes NoteScreen so pop is observable.
class _PopCounter extends NavigatorObserver {
  int pops = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

Widget _host(Widget Function() screen, [NavigatorObserver? observer]) =>
    MaterialApp(
      navigatorObservers: [?observer],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => screen())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('quiz answers are hidden until the question is tapped', (
    tester,
  ) async {
    final (store, dir) = await _setup();
    File('${dir.path}/a.md').writeAsStringSync(
      '# Alpha\n\nHello body text\n\n## Quiz\nQ: Why alpha?\nA: Because first.',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NoteScreen(
          path: 'a.md',
          store: store,
          cacheDir: dir,
          now: () => _now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Why alpha?'), findsOneWidget);
    expect(find.text('Hello body text'), findsOneWidget);
    expect(find.text('Because first.'), findsNothing);
    await tester.tap(find.text('Why alpha?'));
    await tester.pumpAndSettle();
    expect(find.text('Because first.'), findsOneWidget);
  });

  testWidgets('shows note and all four rating buttons', (tester) async {
    final (store, dir) = await _setup();
    await tester.pumpWidget(
      MaterialApp(
        home: NoteScreen(
          path: 'a.md',
          store: store,
          cacheDir: dir,
          now: () => _now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Hello body text'), findsOneWidget);
    for (final label in ['Didn\'t get it', 'Forgot', 'Meh', 'Know it']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('Meh persists dueAt = now + 3 days and pops', (tester) async {
    final (store, dir) = await _setup();
    await tester.pumpWidget(
      _host(
        () => NoteScreen(
          path: 'a.md',
          store: store,
          cacheDir: dir,
          now: () => _now,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meh'));
    await tester.pumpAndSettle();

    expect(find.text('Meh'), findsNothing);
    expect(find.text('open'), findsOneWidget);
    final states = await store.loadStates();
    expect(states['a.md']!.dueAt, DateTime.utc(2026, 5, 4, 12));
  });

  testWidgets('missing note shows message', (tester) async {
    final (store, dir) = await _setup();
    await tester.pumpWidget(
      MaterialApp(
        home: NoteScreen(path: 'gone.md', store: store, cacheDir: dir),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This note no longer exists'), findsOneWidget);
  });

  testWidgets('double tap saves and pops once', (tester) async {
    final (store, dir) = await _setup();
    final observer = _PopCounter();
    await tester.pumpWidget(
      _host(
        () => NoteScreen(
          path: 'a.md',
          store: store,
          cacheDir: dir,
          now: () => _now,
        ),
        observer,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Fire both before any async work completes (taps while the pop animates
    // reach the stale route; tester.tap would miss it).
    FilledButton button(String l) =>
        tester.widget(find.widgetWithText(FilledButton, l));
    final meh = button('Meh').onPressed!;
    final knowIt = button('Know it').onPressed!;
    meh();
    knowIt();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(observer.pops, 1);
    expect(find.text('open'), findsOneWidget);
    expect(find.text('Meh'), findsNothing);
    expect(
      (await store.loadStates())['a.md']!.dueAt,
      DateTime.utc(2026, 5, 4, 12),
    );
  });
}
