import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_nudge/data/store.dart';
import 'package:obsidian_nudge/nudge/nudge.dart';
import 'package:obsidian_nudge/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ThrowingSink implements NotificationSink {
  @override
  Future<void> show({
    required String title,
    required String body,
    required String payload,
  }) async => throw StateError('permission denied');
}

void main() {
  testWidgets('Nudge now failure shows error and re-enables buttons', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store(
      await SharedPreferences.getInstance(),
      MemoryTokenStore(),
    );
    final dir = Directory.systemTemp.createTempSync('settings_screen_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/Study Notes').createSync();
    File('${dir.path}/Study Notes/a.md').writeAsStringSync('# Alpha\n\nbody');

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          store: store,
          cacheDir: dir,
          sink: _ThrowingSink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nudge now'));
    await tester.pumpAndSettle();

    expect(find.textContaining('permission denied'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Sync now'))
          .onPressed,
      isNotNull,
    );
  });
}
