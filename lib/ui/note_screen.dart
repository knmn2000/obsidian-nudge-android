import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';
import '../notes/note.dart';
import '../notes/obsidian_link.dart';
import '../review/scheduler.dart';
import '../sync/github_sync.dart';

class NoteScreen extends StatefulWidget {
  final String path;
  final Store store;
  final Directory cacheDir;
  final DateTime Function() now;

  const NoteScreen({
    super.key,
    required this.path,
    required this.store,
    required this.cacheDir,
    this.now = DateTime.now,
  });

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  late final Future<({Note note, String vault})?> _note = _load();
  bool _rating = false;

  Future<({Note note, String vault})?> _load() async {
    await widget.store.reload();
    final settings = await widget.store.settings();
    for (final n in await loadCachedNotes(widget.cacheDir)) {
      if (n.path == widget.path) {
        return (note: n, vault: settings.obsidianVault);
      }
    }
    return null;
  }

  Future<void> _rate(Rating r) async {
    if (_rating) return;
    setState(() => _rating = true);
    await widget.store.reload();
    final states = await widget.store.loadStates();
    states[widget.path] = rate(r, widget.now());
    await widget.store.saveStates(states);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openInObsidian(String path, String vault) async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await launchUrl(obsidianLink(path, vault: vault));
    } catch (_) {}
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open Obsidian')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({Note note, String vault})?>(
      future: _note,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final loaded = snap.data;
        if (loaded == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This note no longer exists')),
          );
        }
        final (:note, :vault) = loaded;
        return Scaffold(
          appBar: AppBar(
            title: Text(note.title),
            actions: [
              if (vault.isNotEmpty)
                IconButton(
                  tooltip: 'View in Obsidian',
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () => _openInObsidian(note.path, vault),
                ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (note.quiz.isNotEmpty) ...[
                          Text(
                            'Quiz',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          for (final item in note.quiz)
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              childrenPadding: const EdgeInsets.only(
                                bottom: 12,
                              ),
                              expandedCrossAxisAlignment:
                                  CrossAxisAlignment.start,
                              title: Text(item.question),
                              subtitle: const Text('Tap to show answer'),
                              children: [Text(item.answer)],
                            ),
                          const Divider(height: 32),
                        ],
                        MarkdownBody(data: note.body),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (label, r) in [
                        ('Didn\'t get it', Rating.didntGetIt),
                        ('Forgot', Rating.forgot),
                        ('Meh', Rating.meh),
                        ('Know it', Rating.knowIt),
                      ])
                        FilledButton(
                          onPressed: _rating ? null : () => _rate(r),
                          child: Text(label),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
