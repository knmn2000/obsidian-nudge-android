import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../review/scheduler.dart';

class Settings {
  final String repo;
  final String branch;
  final String nudgeFolder;
  final String obsidianVault;
  final int nudgeHours;
  final int quietStart;
  final int quietEnd;

  const Settings({
    this.repo = '',
    this.branch = 'main',
    this.nudgeFolder = '',
    this.obsidianVault = '',
    this.nudgeHours = 5,
    this.quietStart = 23,
    this.quietEnd = 8,
  });

  Settings copyWith({
    String? repo,
    String? branch,
    String? nudgeFolder,
    String? obsidianVault,
    int? nudgeHours,
    int? quietStart,
    int? quietEnd,
  }) => Settings(
    repo: repo ?? this.repo,
    branch: branch ?? this.branch,
    nudgeFolder: nudgeFolder ?? this.nudgeFolder,
    obsidianVault: obsidianVault ?? this.obsidianVault,
    nudgeHours: nudgeHours ?? this.nudgeHours,
    quietStart: quietStart ?? this.quietStart,
    quietEnd: quietEnd ?? this.quietEnd,
  );
}

abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String t);
}

class SecureTokenStore implements TokenStore {
  static const _key = 'github_token';
  final FlutterSecureStorage _s;

  const SecureTokenStore([this._s = const FlutterSecureStorage()]);

  @override
  Future<String?> read() => _s.read(key: _key);

  @override
  Future<void> write(String t) =>
      t.isEmpty ? _s.delete(key: _key) : _s.write(key: _key, value: t);
}

class MemoryTokenStore implements TokenStore {
  String? _t;

  @override
  Future<String?> read() async => _t;

  @override
  Future<void> write(String t) async => _t = t.isEmpty ? null : t;
}

/// Must work from a background isolate: only SharedPreferences + TokenStore.
class Store {
  final SharedPreferences _p;
  final TokenStore _tokens;

  Store(this._p, this._tokens);

  static const _states = 'review_states';
  static const _lastSync = 'last_sync';
  static const _lastSyncError = 'last_sync_error';

  /// The background isolate writes prefs; re-read them in the foreground.
  Future<void> reload() => _p.reload();

  Future<String?> token() => _tokens.read();
  Future<void> setToken(String t) => _tokens.write(t);

  Future<Settings> settings() async {
    const d = Settings();
    return Settings(
      repo: _p.getString('repo') ?? d.repo,
      branch: _p.getString('branch') ?? d.branch,
      nudgeFolder: _p.getString('nudge_folder') ?? d.nudgeFolder,
      obsidianVault: _p.getString('obsidian_vault') ?? d.obsidianVault,
      nudgeHours: _p.getInt('nudge_hours') ?? d.nudgeHours,
      quietStart: _p.getInt('quiet_start') ?? d.quietStart,
      quietEnd: _p.getInt('quiet_end') ?? d.quietEnd,
    );
  }

  Future<void> saveSettings(Settings s) async {
    await _p.setString('repo', s.repo);
    await _p.setString('branch', s.branch);
    await _p.setString('nudge_folder', s.nudgeFolder);
    await _p.setString('obsidian_vault', s.obsidianVault);
    await _p.setInt('nudge_hours', s.nudgeHours);
    await _p.setInt('quiet_start', s.quietStart);
    await _p.setInt('quiet_end', s.quietEnd);
  }

  Future<Map<String, ReviewState>> loadStates() async {
    final raw = _p.getString(_states);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, ReviewState.fromJson(v as Map<String, dynamic>)),
      );
    } catch (_) {
      // Corrupt prefs must not crash the background job.
      return {};
    }
  }

  Future<void> saveStates(Map<String, ReviewState> states) => _p.setString(
    _states,
    jsonEncode(states.map((k, v) => MapEntry(k, v.toJson()))),
  );

  DateTime? get lastSync {
    final s = _p.getString(_lastSync);
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> setLastSync(DateTime t) =>
      _p.setString(_lastSync, t.toUtc().toIso8601String());

  String? get lastSyncError => _p.getString(_lastSyncError);

  Future<void> setLastSyncError(String? e) =>
      e == null ? _p.remove(_lastSyncError) : _p.setString(_lastSyncError, e);
}
