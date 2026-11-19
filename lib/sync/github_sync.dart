import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import '../notes/note.dart';

class SyncException implements Exception {
  final int? statusCode;
  final String message;

  const SyncException(this.message, {this.statusCode});

  @override
  String toString() => 'SyncException: $message';
}

String _httpMessage(int code) => switch (code) {
  401 => 'GitHub rejected the token (401). It may have expired.',
  403 => 'GitHub denied access (403). Check the token permissions.',
  404 => 'Repo or branch not found (404). Check the repo and branch.',
  _ => 'GitHub returned an error ($code).',
};

/// Downloads the repo zipball and replaces [cacheDir] with its notes.
/// Returns the number of notes written. The old cache is only replaced after
/// a full successful extraction.
Future<int> syncNotes({
  required http.Client client,
  required String token,
  required String repo,
  required String branch,
  required Directory cacheDir,
}) async {
  final http.Response res;
  try {
    res = await client
        .get(
          Uri(
            scheme: 'https',
            host: 'api.github.com',
            pathSegments: ['repos', ...repo.split('/'), 'zipball', branch],
          ),
          headers: {
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
            'Accept': 'application/vnd.github+json',
          },
        )
        .timeout(const Duration(seconds: 60));
  } on IOException {
    throw const SyncException('Network error while contacting GitHub.');
  } on http.ClientException {
    throw const SyncException('Network error while contacting GitHub.');
  } on TimeoutException {
    throw const SyncException('Sync timed out. Try again.');
  }
  if (res.statusCode != 200) {
    throw SyncException(
      _httpMessage(res.statusCode),
      statusCode: res.statusCode,
    );
  }

  final tmp = Directory('${cacheDir.path}.tmp');
  var count = 0;
  try {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    tmp.createSync(recursive: true);
    final archive = ZipDecoder().decodeBytes(res.bodyBytes);
    // The decoder returns an empty archive for non-zip bytes.
    if (archive.isEmpty) throw const FormatException('empty archive');
    for (final entry in archive) {
      if (!entry.isFile) continue;
      // Drop the single top-level "owner-repo-<sha>/" folder.
      final slash = entry.name.indexOf('/');
      if (slash == -1) continue;
      final path = entry.name.substring(slash + 1);
      final segments = path.split('/');
      if (path.startsWith('/') || segments.contains('..')) continue; // zip-slip
      if (!isNotePath(path)) continue;
      final file = File('${tmp.path}/$path')
        ..parent.createSync(recursive: true);
      file.writeAsStringSync(
        utf8.decode(entry.readBytes()!, allowMalformed: true),
        encoding: utf8,
      );
      count++;
    }
  } catch (_) {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    throw const SyncException('Could not read the downloaded archive.');
  }

  if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
  tmp.renameSync(cacheDir.path);
  return count;
}

Future<List<Note>> loadCachedNotes(Directory cacheDir) async {
  if (!cacheDir.existsSync()) return [];
  final root = cacheDir.path;
  final notes = <Note>[];
  for (final f in cacheDir.listSync(recursive: true).whereType<File>()) {
    final rel = f.path.substring(root.length + 1).replaceAll('\\', '/');
    if (!rel.endsWith('.md')) continue;
    final note = parseNote(
      rel,
      utf8.decode(f.readAsBytesSync(), allowMalformed: true),
    );
    if (note != null) notes.add(note);
  }
  notes.sort((a, b) => a.path.compareTo(b.path));
  return notes;
}
