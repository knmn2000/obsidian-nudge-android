import 'dart:io';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../nudge/nudge.dart';
import '../sync/github_sync.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final Store store;
  final Directory cacheDir;
  final NotificationSink sink;

  const HomeScreen({
    super.key,
    required this.store,
    required this.cacheDir,
    required this.sink,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int? _count;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    await widget.store.reload();
    final n = (await loadCachedNotes(widget.cacheDir)).length;
    if (mounted) setState(() => _count = n);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Obsidian Nudge')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _count == null ? 'Loading…' : '$_count notes cached',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context)
                  .push(
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsScreen(
                        store: widget.store,
                        cacheDir: widget.cacheDir,
                        sink: widget.sink,
                      ),
                    ),
                  )
                  .then((_) => _refresh()),
              child: const Text('Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
