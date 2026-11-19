import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/store.dart';
import '../nudge/background.dart';
import '../nudge/nudge.dart';
import '../sync/github_sync.dart';
import 'setup_screen.dart';

/// Like [runSync] but throws, so the caller can show the error.
Future<void> syncOrThrow(
  Store store,
  Directory cacheDir, {
  Settings? settings,
  String? token,
}) async {
  final s = settings ?? await store.settings();
  final client = http.Client();
  try {
    await syncNotes(
      client: client,
      token: token ?? await store.token() ?? '',
      repo: s.repo,
      branch: s.branch,
      cacheDir: cacheDir,
    );
    await store.setLastSync(DateTime.now());
    await store.setLastSyncError(null);
  } finally {
    client.close();
  }
}

class SettingsScreen extends StatefulWidget {
  final Store store;
  final Directory cacheDir;
  final NotificationSink sink;

  const SettingsScreen({
    super.key,
    required this.store,
    required this.cacheDir,
    required this.sink,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Settings? _settings;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    await widget.store.reload();
    final s = await widget.store.settings();
    if (mounted) setState(() => _settings = s);
  }

  Future<void> _save(Settings s) async {
    setState(() => _settings = s);
    await widget.store.saveSettings(s);
    await scheduleWork(s);
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _sync() async {
    setState(() => _busy = true);
    try {
      try {
        await syncOrThrow(widget.store, widget.cacheDir);
      } catch (e) {
        await widget.store.setLastSyncError(
          e is SyncException ? e.message : e.toString(),
        );
      }
      await _refresh();
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _nudge() async {
    setState(() => _busy = true);
    try {
      await widget.store.reload();
      final sent = await runNudge(
        store: widget.store,
        cacheDir: widget.cacheDir,
        sink: widget.sink,
        now: DateTime.now(),
        rng: Random(),
        ignoreQuietHours: true,
      );
      if (mounted) {
        _snack(sent ? 'Notification sent' : 'No note is due, nothing sent');
      }
    } catch (e) {
      if (mounted) _snack('Nudge failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _hours(
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> on,
  ) {
    return ListTile(
      title: Text(label),
      trailing: DropdownButton<int>(
        value: value,
        items: [
          for (var h = min; h <= max; h++)
            DropdownMenuItem(value: h, child: Text('$h')),
        ],
        onChanged: (v) {
          if (v != null) on(v);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    final store = widget.store;
    final err = store.lastSyncError;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _hours(
                  'Nudge every (hours)',
                  s.nudgeHours,
                  1,
                  24,
                  (v) => _save(s.copyWith(nudgeHours: v)),
                ),
                _hours(
                  'Quiet hours start',
                  s.quietStart,
                  0,
                  23,
                  (v) => _save(s.copyWith(quietStart: v)),
                ),
                _hours(
                  'Quiet hours end',
                  s.quietEnd,
                  0,
                  23,
                  (v) => _save(s.copyWith(quietEnd: v)),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Last sync'),
                  subtitle: Text(
                    store.lastSync?.toLocal().toString() ?? 'Never',
                  ),
                ),
                if (err != null)
                  ListTile(
                    title: const Text('Last sync error'),
                    subtitle: Text(err),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _busy ? null : _sync,
                        child: const Text('Sync now'),
                      ),
                      FilledButton(
                        onPressed: _busy ? null : _nudge,
                        child: const Text('Nudge now'),
                      ),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context)
                            .push(
                              MaterialPageRoute<void>(
                                builder: (ctx) => SetupScreen(
                                  store: store,
                                  syncNow: (settings, token) => syncOrThrow(
                                    store,
                                    widget.cacheDir,
                                    settings: settings,
                                    token: token,
                                  ),
                                  onDone: () => Navigator.of(ctx).pop(),
                                ),
                              ),
                            )
                            .then((_) => _refresh()),
                        child: const Text('Vault setup'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
