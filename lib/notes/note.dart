class QuizItem {
  final String question;
  final String answer;
  const QuizItem(this.question, this.answer);
}

class Note {
  final String path;
  final String title;
  final String firstLine;

  /// Note text without the `## Quiz` section.
  final String body;
  final List<QuizItem> quiz;

  const Note({
    required this.path,
    required this.title,
    required this.firstLine,
    required this.body,
    this.quiz = const [],
  });
}

final _quizHeading = RegExp(r'^##\s+quiz\s*$', caseSensitive: false);

bool _isFence(String line) {
  final t = line.trim();
  return t.startsWith('```') || t.startsWith('~~~');
}

/// Splits a `## Quiz` section (ends at the next heading of level 1-2) out of
/// [lines]. Inside it, `Q:` starts a question and `A:` its answer; other
/// non-empty lines continue whichever of the two came last.
(List<String>, List<QuizItem>) _splitQuiz(List<String> lines) {
  final rest = <String>[];
  final quiz = <QuizItem>[];
  var inFence = false;
  var inQuiz = false;
  String? q;
  String? a;

  void flush() {
    if (q != null && a != null && q!.isNotEmpty && a!.isNotEmpty) {
      quiz.add(QuizItem(q!, a!));
    }
    q = null;
    a = null;
  }

  for (final line in lines) {
    final t = line.trim();
    if (_isFence(line)) inFence = !inFence;
    if (!inQuiz) {
      if (!inFence && _quizHeading.hasMatch(t)) {
        inQuiz = true;
      } else {
        rest.add(line);
      }
      continue;
    }
    if (!inFence && (t.startsWith('# ') || t.startsWith('## '))) {
      flush();
      inQuiz = false;
      rest.add(line);
    } else if (t.startsWith('Q:')) {
      flush();
      q = t.substring(2).trim();
    } else if (t.startsWith('A:') && q != null) {
      a = t.substring(2).trim();
    } else if (t.isNotEmpty) {
      if (a != null) {
        a = '$a\n$t';
      } else if (q != null) {
        q = '$q\n$t';
      }
    }
  }
  flush();
  return (rest, quiz);
}

final _dailyName = RegExp(r'^\d{4}-\d{2}-\d{2}\.md$');
final _wikilink = RegExp(r'\[\[([^\]|]*)(?:\|([^\]]*))?\]\]');

bool isNotePath(String path) {
  if (!path.endsWith('.md') || path.endsWith('.excalidraw.md')) return false;
  final parts = path.split('/');
  final name = parts.last;
  if (parts
      .take(parts.length - 1)
      .any((d) => d == '.obsidian' || d == '.git' || d == 'Excalidraw')) {
    return false;
  }
  return name != 'KANBAN.md' &&
      name != 'Untitled.md' &&
      !_dailyName.hasMatch(name);
}

Note? parseNote(String path, String content) {
  if (!isNotePath(path) || content.trim().isEmpty) return null;

  var lines = content.split('\n');
  if (lines.first.trim() == '---') {
    final end = lines.indexWhere((l) => l.trim() == '---', 1);
    if (end != -1) lines = lines.sublist(end + 1);
  }
  final (rest, quiz) = _splitQuiz(lines);
  lines = rest;
  final body = lines.join('\n').trim();

  String? title;
  var firstLine = '';
  var inFence = false;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.startsWith('```') || line.startsWith('~~~')) {
      inFence = !inFence;
      continue;
    }
    if (inFence || line.isEmpty) continue;
    if (line.startsWith('#')) {
      if (title == null && line.startsWith('# ')) {
        title = line.substring(2).trim();
      }
      continue;
    }
    if (firstLine.isEmpty) firstLine = line;
  }

  firstLine = firstLine.replaceAllMapped(
    _wikilink,
    (m) => (m[2] ?? '').isNotEmpty ? m[2]! : m[1]!,
  );
  if (firstLine.length > 140) firstLine = '${firstLine.substring(0, 139)}…';

  final fileName = path.split('/').last;
  return Note(
    path: path,
    title: title ?? fileName.substring(0, fileName.length - 3),
    firstLine: firstLine,
    body: body,
    quiz: quiz,
  );
}
