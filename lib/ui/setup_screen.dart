import 'package:flutter/material.dart';

import '../data/store.dart';
import '../sync/github_sync.dart';

class SetupScreen extends StatefulWidget {
  final Store store;
  final Future<void> Function(Settings settings, String token) syncNow;
  final VoidCallback onDone;

  const SetupScreen({
    super.key,
    required this.store,
    required this.syncNow,
    required this.onDone,
  });

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _token = TextEditingController();
  final _repo = TextEditingController();
  final _branch = TextEditingController();
  final _folder = TextEditingController();
  final _vault = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.store.settings().then((s) {
      if (!mounted) return;
      _repo.text = s.repo;
      _branch.text = s.branch;
      _folder.text = s.nudgeFolder;
      _vault.text = s.obsidianVault;
    });
    widget.store
        .token()
        .then((token) {
          if (mounted && _token.text.isEmpty) _token.text = token ?? '';
        })
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _token.dispose();
    _repo.dispose();
    _branch.dispose();
    _folder.dispose();
    _vault.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await widget.store.settings();
      final token = _token.text.trim();
      final next = s.copyWith(
        repo: _repo.text.trim(),
        branch: _branch.text.trim(),
        nudgeFolder: _folder.text.trim().replaceAll(RegExp(r'^/+|/+$'), ''),
        obsidianVault: _vault.text.trim(),
      );
      await widget.syncNow(next, token);
      await widget.store.setToken(token);
      await widget.store.saveSettings(next);
      if (s.repo != next.repo || s.branch != next.branch) {
        await widget.store.saveStates({});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is SyncException ? e.message : e.toString();
      });
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onDone();
  }

  String? _required(String? v, String msg) =>
      (v == null || v.trim().isEmpty) ? msg : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect GitHub')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('token'),
                  controller: _token,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'GitHub token',
                    helperText: 'Required for private repositories',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('repo'),
                  controller: _repo,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Repository (owner/name)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      RegExp(
                        r'^[a-zA-Z0-9-]+/[a-zA-Z0-9_.-]+$',
                      ).hasMatch(v?.trim() ?? '')
                      ? null
                      : 'Enter the repository as owner/name',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('branch'),
                  controller: _branch,
                  decoration: const InputDecoration(
                    labelText: 'Branch',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => _required(v, 'Branch is required'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('nudgeFolder'),
                  controller: _folder,
                  decoration: const InputDecoration(
                    labelText: 'Nudge folder (optional)',
                    helperText:
                        'Path in the vault. Blank uses the whole vault.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('obsidianVault'),
                  controller: _vault,
                  decoration: const InputDecoration(
                    labelText: 'Obsidian vault name (optional)',
                    helperText:
                        'Vault name on this phone, for opening notes in Obsidian.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Syncing…' : 'Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
