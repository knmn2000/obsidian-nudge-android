import 'dart:math';

import '../notes/note.dart';

enum Rating { didntGetIt, forgot, meh, knowIt }

class ReviewState {
  final DateTime dueAt;
  final DateTime? snoozedUntil;

  const ReviewState({required this.dueAt, this.snoozedUntil});

  Map<String, dynamic> toJson() => {
    // UTC so the instant survives timezone/DST changes.
    'dueAt': dueAt.toUtc().toIso8601String(),
    'snoozedUntil': snoozedUntil?.toUtc().toIso8601String(),
  };

  factory ReviewState.fromJson(Map<String, dynamic> j) => ReviewState(
    dueAt: DateTime.parse(j['dueAt'] as String),
    snoozedUntil: j['snoozedUntil'] == null
        ? null
        : DateTime.parse(j['snoozedUntil'] as String),
  );
}

// 4h, not 5h: WorkManager jitter must not make it miss the next nudge.
ReviewState rate(Rating r, DateTime now) => ReviewState(
  dueAt: now.add(switch (r) {
    Rating.didntGetIt => const Duration(hours: 4),
    Rating.forgot => const Duration(days: 1),
    Rating.meh => const Duration(days: 3),
    Rating.knowIt => const Duration(days: 21),
  }),
);

ReviewState snooze(ReviewState? s, DateTime now) => ReviewState(
  dueAt: s?.dueAt ?? now,
  snoozedUntil: now.add(const Duration(days: 1)),
);

Note? pickNext(
  List<Note> notes,
  Map<String, ReviewState> states,
  DateTime now,
  Random rng,
) {
  var best = <Note>[];
  DateTime? bestDue;
  for (final note in notes) {
    final s = states[note.path];
    final due = s?.dueAt ?? now;
    final snoozed = s?.snoozedUntil;
    if (due.isAfter(now) || (snoozed != null && snoozed.isAfter(now))) continue;
    if (bestDue == null || due.isBefore(bestDue)) {
      bestDue = due;
      best = [note];
    } else if (due.isAtSameMomentAs(bestDue)) {
      best.add(note);
    }
  }
  return best.isEmpty ? null : best[rng.nextInt(best.length)];
}

bool inQuietHours(DateTime now, {int startHour = 23, int endHour = 8}) {
  final h = now.hour;
  return startHour < endHour
      ? h >= startHour && h < endHour
      : h >= startHour || h < endHour;
}
