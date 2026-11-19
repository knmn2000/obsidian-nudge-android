import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:obsidian_nudge/sync/github_sync.dart';

List<int> zipOf(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encode(archive);
}

void main() {
  late Directory tmp;
  late Directory cache;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sync_test');
    cache = Directory('${tmp.path}/cache');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<int> run(http.Client client) => syncNotes(
    client: client,
    token: 'tok123',
    repo: 'owner/repo',
    branch: 'main',
    cacheDir: cache,
  );

  test(
    'extracts notes without top folder, keeps unicode, skips non-notes',
    () async {
      final zip = zipOf({
        'owner-repo-abc123/': '',
        'owner-repo-abc123/Study Notes/General terms/café.md': '# Café\nhello',
        'owner-repo-abc123/Top.md': 'top',
        'owner-repo-abc123/.obsidian/app.md': 'x',
        'owner-repo-abc123/KANBAN.md': 'x',
        'owner-repo-abc123/img.png': 'x',
        'owner-repo-abc123/../evil.md': 'x',
        'owner-repo-abc123/a/../../evil2.md': 'x',
      });
      final n = await run(
        MockClient((_) async => http.Response.bytes(zip, 200)),
      );
      expect(n, 2);
      final notes = await loadCachedNotes(cache);
      expect(notes.map((e) => e.path).toList(), [
        'Study Notes/General terms/café.md',
        'Top.md',
      ]);
      expect(notes.first.title, 'Café');
      expect(notes.first.body, '# Café\nhello');
      expect(File('${tmp.path}/evil.md').existsSync(), isFalse);
      expect(File('${cache.path}/evil.md').existsSync(), isFalse);
      expect(Directory('${cache.path}.tmp').existsSync(), isFalse);
    },
  );

  test('sends bearer header to zipball url', () async {
    late http.Request seen;
    await run(
      MockClient((r) async {
        seen = r;
        return http.Response.bytes(zipOf({'o-r-1/a.md': 'a'}), 200);
      }),
    );
    expect(
      seen.url.toString(),
      'https://api.github.com/repos/owner/repo/zipball/main',
    );
    expect(seen.headers['Authorization'], 'Bearer tok123');
    expect(seen.headers['Accept'], 'application/vnd.github+json');
  });

  test('401 throws and leaves cache untouched', () async {
    cache.createSync();
    File('${cache.path}/old.md').writeAsStringSync('old');
    await expectLater(
      run(MockClient((_) async => http.Response('nope', 401))),
      throwsA(
        isA<SyncException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', isNot(contains('tok123'))),
      ),
    );
    expect(File('${cache.path}/old.md').readAsStringSync(), 'old');
  });

  test(
    'socket error throws SyncException and leaves cache untouched',
    () async {
      cache.createSync();
      File('${cache.path}/old.md').writeAsStringSync('old');
      await expectLater(
        run(MockClient((_) async => throw const SocketException('down'))),
        throwsA(isA<SyncException>().having((e) => e.statusCode, 'code', null)),
      );
      expect(File('${cache.path}/old.md').readAsStringSync(), 'old');
    },
  );

  for (final (name, error) in <(String, Object)>[
    ('handshake', const HandshakeException('x')),
    ('client', http.ClientException('x')),
    ('timeout', TimeoutException('x')),
  ]) {
    test(
      '$name error throws SyncException and leaves cache untouched',
      () async {
        cache.createSync();
        File('${cache.path}/old.md').writeAsStringSync('old');
        await expectLater(
          run(MockClient((_) async => throw error)),
          throwsA(
            isA<SyncException>()
                .having((e) => e.statusCode, 'code', null)
                .having((e) => e.message, 'message', isNot(contains('tok123'))),
          ),
        );
        expect(File('${cache.path}/old.md').readAsStringSync(), 'old');
      },
    );
  }

  test('corrupt zip throws and leaves cache untouched', () async {
    cache.createSync();
    File('${cache.path}/old.md').writeAsStringSync('old');
    await expectLater(
      run(MockClient((_) async => http.Response('not a zip', 200))),
      throwsA(isA<SyncException>()),
    );
    expect(File('${cache.path}/old.md').readAsStringSync(), 'old');
    expect(Directory('${cache.path}.tmp').existsSync(), isFalse);
  });

  test('second sync removes note deleted upstream', () async {
    await run(
      MockClient(
        (_) async => http.Response.bytes(
          zipOf({'o-r-1/a.md': 'a', 'o-r-1/b.md': 'b'}),
          200,
        ),
      ),
    );
    expect((await loadCachedNotes(cache)).map((n) => n.path), ['a.md', 'b.md']);
    await run(
      MockClient(
        (_) async => http.Response.bytes(zipOf({'o-r-2/a.md': 'a'}), 200),
      ),
    );
    expect((await loadCachedNotes(cache)).map((n) => n.path), ['a.md']);
  });

  test('loadCachedNotes on missing dir is empty', () async {
    expect(await loadCachedNotes(cache), isEmpty);
  });
}
