import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_nudge/data/store.dart';
import 'package:obsidian_nudge/sync/github_sync.dart';
import 'package:obsidian_nudge/ui/setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(Store, MemoryTokenStore)> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final tokens = MemoryTokenStore();
  return (Store(await SharedPreferences.getInstance(), tokens), tokens);
}

Future<void> _pump(
  WidgetTester tester,
  Store store,
  Future<void> Function() syncNow,
  VoidCallback onDone,
) => tester.pumpWidget(
  MaterialApp(
    home: SetupScreen(
      store: store,
      syncNow: (_, _) => syncNow(),
      onDone: onDone,
    ),
  ),
);

void main() {
  testWidgets('prefills the branch and leaves the vault details blank', (
    tester,
  ) async {
    final (store, _) = await _setup();
    await _pump(tester, store, () async {}, () {});
    await tester.pumpAndSettle();
    for (final field in ['repo', 'nudgeFolder', 'obsidianVault', 'token']) {
      expect(
        tester.widget<TextFormField>(find.byKey(Key(field))).controller!.text,
        isEmpty,
      );
    }
    expect(find.text('main'), findsOneWidget);
  });

  testWidgets('Save stores trimmed token and settings, syncs, calls onDone', (
    tester,
  ) async {
    final (store, tokens) = await _setup();
    var synced = 0;
    var done = 0;
    await _pump(tester, store, () async => synced++, () => done++);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('token')), '  test-token  ');
    await tester.enterText(find.byKey(const Key('repo')), 'a/b');
    await tester.enterText(find.byKey(const Key('branch')), 'dev');
    await tester.enterText(
      find.byKey(const Key('nudgeFolder')),
      ' /Study/Review/ ',
    );
    await tester.enterText(
      find.byKey(const Key('obsidianVault')),
      ' My Vault ',
    );
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await tokens.read(), 'test-token');
    final s = await store.settings();
    expect(s.repo, 'a/b');
    expect(s.branch, 'dev');
    expect(s.nudgeFolder, 'Study/Review');
    expect(s.obsidianVault, 'My Vault');
    expect(synced, 1);
    expect(done, 1);
  });

  testWidgets('sync failure shows error, no token leak, no onDone', (
    tester,
  ) async {
    final (store, _) = await _setup();
    await store.saveSettings(const Settings(repo: 'owner/previous'));
    await store.setToken('previous-token');
    var done = 0;
    await _pump(
      tester,
      store,
      () async => throw const SyncException('Bad credentials'),
      () => done++,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('token')),
      'example-private-token',
    );
    await tester.enterText(find.byKey(const Key('repo')), 'owner/replacement');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Bad credentials'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains('example-private-token'),
      ),
      findsNothing,
    );
    expect(done, 0);
    expect((await store.settings()).repo, 'owner/previous');
    expect(await store.token(), 'previous-token');
  });

  testWidgets('a missing repository shows validation and does not sync', (
    tester,
  ) async {
    final (store, tokens) = await _setup();
    var synced = 0;
    await _pump(tester, store, () async => synced++, () {});
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('token')), '   ');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Enter the repository as owner/name'), findsOneWidget);
    expect(await tokens.read(), isNull);
    expect(synced, 0);
  });
}
