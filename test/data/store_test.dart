import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_nudge/data/store.dart';
import 'package:obsidian_nudge/review/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(Store, SharedPreferences, MemoryTokenStore)> make([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final tokens = MemoryTokenStore();
  return (Store(prefs, tokens), prefs, tokens);
}

void main() {
  test('fresh store returns defaults', () async {
    final (store, _, _) = await make();
    final s = await store.settings();
    expect(s.repo, isEmpty);
    expect(s.nudgeFolder, isEmpty);
    expect(s.obsidianVault, isEmpty);
    expect(s.branch, 'main');
    expect(s.nudgeHours, 5);
    expect(s.quietStart, 23);
    expect(s.quietEnd, 8);
    expect(await store.token(), isNull);
    expect(await store.loadStates(), isEmpty);
    expect(store.lastSync, isNull);
    expect(store.lastSyncError, isNull);
  });

  test('settings round-trip', () async {
    final (store, prefs, _) = await make();
    await store.saveSettings(
      const Settings().copyWith(
        repo: 'a/b',
        branch: 'dev',
        nudgeFolder: 'Study',
        obsidianVault: 'My Vault',
        nudgeHours: 3,
        quietStart: 22,
        quietEnd: 7,
      ),
    );
    final s = await Store(prefs, MemoryTokenStore()).settings();
    expect(s.repo, 'a/b');
    expect(s.branch, 'dev');
    expect(s.nudgeFolder, 'Study');
    expect(s.obsidianVault, 'My Vault');
    expect(s.nudgeHours, 3);
    expect(s.quietStart, 22);
    expect(s.quietEnd, 7);
  });

  test('states round-trip incl. null snoozedUntil', () async {
    final (store, prefs, _) = await make();
    final due = DateTime.utc(2026, 1, 2, 3);
    final snooze = DateTime.utc(2026, 1, 5);
    await store.saveStates({
      'a.md': ReviewState(dueAt: due, snoozedUntil: null),
      'b.md': ReviewState(dueAt: due, snoozedUntil: snooze),
    });
    final out = await Store(prefs, MemoryTokenStore()).loadStates();
    expect(out.keys.toSet(), {'a.md', 'b.md'});
    expect(out['a.md']!.dueAt, due);
    expect(out['a.md']!.snoozedUntil, isNull);
    expect(out['b.md']!.snoozedUntil, snooze);
  });

  test('corrupt states json yields empty map', () async {
    final (store, _, _) = await make({'review_states': '{not json'});
    expect(await store.loadStates(), isEmpty);
  });

  test('token round-trip and never in SharedPreferences', () async {
    final (store, prefs, tokens) = await make();
    await store.setToken('example-private-token');
    expect(await store.token(), 'example-private-token');
    expect(await tokens.read(), 'example-private-token');
    await store.saveSettings(const Settings());
    await store.saveStates({'a.md': ReviewState(dueAt: DateTime.utc(2026))});
    for (final k in prefs.getKeys()) {
      expect(k.contains('example-private-token'), isFalse);
      expect(
        prefs.get(k).toString().contains('example-private-token'),
        isFalse,
      );
    }
  });

  test('lastSync and error persist and clear', () async {
    final (store, _, _) = await make();
    final t = DateTime.utc(2026, 3, 4, 5, 6, 7);
    await store.setLastSync(t);
    await store.setLastSyncError('boom');
    expect(store.lastSync, t);
    expect(store.lastSync!.isUtc, isTrue);
    expect(store.lastSyncError, 'boom');
    await store.setLastSyncError(null);
    expect(store.lastSyncError, isNull);
  });

  test('reload picks up writes made by another isolate', () async {
    final (store, _, _) = await make();
    expect(await store.loadStates(), isEmpty);
    SharedPreferences.setMockInitialValues({
      'review_states':
          '{"a.md":{"dueAt":"2026-01-02T00:00:00.000Z","snoozedUntil":null}}',
    });
    await store.reload();
    expect((await store.loadStates())['a.md']!.dueAt, DateTime.utc(2026, 1, 2));
  });
}
