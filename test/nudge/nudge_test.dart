import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:obsidian_nudge/data/store.dart';
import 'package:obsidian_nudge/nudge/nudge.dart';
import 'package:obsidian_nudge/review/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSink implements NotificationSink {
  final calls = <(String, String, String)>[];

  @override
  Future<void> show({
    required String title,
    required String body,
    required String payload,
  }) async => calls.add((title, body, payload));
}

void main() {
  final now = DateTime(2026, 11, 15, 12);
  late Directory tmp;
  late Directory cache;
  late Store store;
  late FakeSink sink;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = Store(await SharedPreferences.getInstance(), MemoryTokenStore());
    sink = FakeSink();
    tmp = Directory.systemTemp.createTempSync('nudge_test');
    cache = Directory('${tmp.path}/cache')..createSync();
    File('${cache.path}/a.md').writeAsStringSync('# Alpha\nfirst alpha line');
    File('${cache.path}/b.md').writeAsStringSync('# Beta\n');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<bool> nudge(DateTime at, {bool ignoreQuietHours = false}) => runNudge(
    store: store,
    cacheDir: cache,
    sink: sink,
    now: at,
    rng: Random(1),
    ignoreQuietHours: ignoreQuietHours,
  );

  Future<void> notDue(String path) =>
      store.saveStates({path: ReviewState(dueAt: now.add(Duration(days: 1)))});

  group('runNudge', () {
    test(
      'shows title, firstLine and path for a due note, then snoozes it',
      () async {
        await notDue('b.md');
        expect(await nudge(now), isTrue);
        expect(sink.calls, [('Alpha', 'first alpha line', 'a.md')]);
        final states = await store.loadStates();
        expect(
          states['a.md']!.snoozedUntil,
          now.add(Duration(days: 1)).toUtc(),
        );
        expect(states['b.md']!.dueAt, now.add(Duration(days: 1)).toUtc());
      },
    );

    test(
      'configured folder nudges only its own notes and descendants',
      () async {
        await store.saveSettings(const Settings(nudgeFolder: 'Study Notes'));
        Directory('${cache.path}/Study Notes').createSync();
        File('${cache.path}/Study Notes/c.md').writeAsStringSync('# Gamma\ng');
        File('${cache.path}/Study Notesed.md').writeAsStringSync('# Decoy\nd');
        final ok = await runNudge(
          store: store,
          cacheDir: cache,
          sink: sink,
          now: now,
          rng: Random(1),
        );
        expect(ok, isTrue);
        expect(sink.calls, [('Gamma', 'g', 'Study Notes/c.md')]);
      },
    );

    test('note with a quiz nudges with one of its questions', () async {
      File(
        '${cache.path}/a.md',
      ).writeAsStringSync('# Alpha\nbody\n\n## Quiz\nQ: Why?\nA: Because.');
      await notDue('b.md');
      expect(await nudge(now), isTrue);
      expect(sink.calls, [('Alpha', 'Quiz: Why?', 'a.md')]);
    });

    test('nothing to nudge when the folder has no notes', () async {
      await store.saveSettings(const Settings(nudgeFolder: 'Missing folder'));
      final ok = await runNudge(
        store: store,
        cacheDir: cache,
        sink: sink,
        now: now,
        rng: Random(1),
      );
      expect(ok, isFalse);
      expect(sink.calls, isEmpty);
    });

    test('empty firstLine falls back to the title', () async {
      await notDue('a.md');
      expect(await nudge(now), isTrue);
      expect(sink.calls, [('Beta', 'Beta', 'b.md')]);
    });

    test('shows nothing and saves nothing in quiet hours', () async {
      expect(await nudge(DateTime(2026, 11, 15, 2)), isFalse);
      expect(sink.calls, isEmpty);
      expect(await store.loadStates(), isEmpty);
    });

    test('ignoreQuietHours nudges at 02:00', () async {
      expect(
        await nudge(DateTime(2026, 11, 15, 2), ignoreQuietHours: true),
        isTrue,
      );
      expect(sink.calls, hasLength(1));
    });

    test('shows nothing with an empty cache', () async {
      cache.deleteSync(recursive: true);
      expect(await nudge(now), isFalse);
      expect(sink.calls, isEmpty);
      expect(await store.loadStates(), isEmpty);
    });

    test(
      'nudged note is not picked again 5h later, the other one is',
      () async {
        expect(await nudge(now), isTrue);
        expect(await nudge(now.add(Duration(hours: 5))), isTrue);
        final paths = sink.calls.map((c) => c.$3).toList();
        expect(paths.toSet(), {'a.md', 'b.md'});
        expect(await nudge(now.add(Duration(hours: 10))), isFalse);
        expect(sink.calls, hasLength(2));
      },
    );
  });

  group('runSync', () {
    Future<void> sync(http.Client client) =>
        runSync(store: store, cacheDir: cache, client: client, now: now);

    test('without a configured repository does nothing', () async {
      var called = false;
      await sync(
        MockClient((_) async {
          called = true;
          return http.Response('', 200);
        }),
      );
      expect(called, isFalse);
      expect(store.lastSync, isNull);
      expect(store.lastSyncError, isNull);
    });

    test('401 stores the error and keeps the cache', () async {
      await store.saveSettings(const Settings(repo: 'owner/repo'));
      await store.setToken('tok');
      await sync(MockClient((_) async => http.Response('', 401)));
      expect(
        store.lastSyncError,
        'GitHub rejected the token (401). It may have expired.',
      );
      expect(store.lastSync, isNull);
      expect(
        File('${cache.path}/a.md').readAsStringSync(),
        '# Alpha\nfirst alpha line',
      );
    });

    test('public repo syncs without a token and clears the error', () async {
      await store.saveSettings(const Settings(repo: 'owner/repo'));
      await store.setLastSyncError('old');
      final archive = Archive();
      final bytes = utf8.encode('# New\nfresh');
      archive.addFile(ArchiveFile('o-r-1/new.md', bytes.length, bytes));
      await sync(
        MockClient((request) async {
          expect(request.headers['Authorization'], isNull);
          return http.Response.bytes(ZipEncoder().encode(archive), 200);
        }),
      );
      expect(store.lastSync, now.toUtc());
      expect(store.lastSyncError, isNull);
      expect(File('${cache.path}/new.md').existsSync(), isTrue);
    });
  });
}
