import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PhoneSession {
  PhoneSession({required this.id, required this.name, required this.serverUrl});

  final String id;
  String name;
  String serverUrl;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'serverUrl': serverUrl};

  factory PhoneSession.fromJson(Map<String, dynamic> j) => PhoneSession(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        serverUrl: j['serverUrl'] as String,
      );
}

class SessionManager extends ChangeNotifier {
  final List<PhoneSession> sessions = [];
  String? _activeId;
  bool _loaded = false;

  PhoneSession? get active {
    for (final s in sessions) {
      if (s.id == _activeId) return s;
    }
    return sessions.isNotEmpty ? sessions.first : null;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('sessions');
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final e in list) {
          sessions.add(PhoneSession.fromJson(e as Map<String, dynamic>));
        }
      } catch (_) {}
    }

    if (sessions.isEmpty) {
      sessions.add(PhoneSession(
        id: 'local',
        name: 'Local relay',
        serverUrl: 'ws://127.0.0.1:8765',
      ));
    }

    _activeId = prefs.getString('active-session');
    if (active == null) _activeId = sessions.first.id;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'sessions',
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
    await prefs.setString('active-session', _activeId ?? '');
  }

  Future<void> add(String name, String serverUrl) async {
    final url = serverUrl.trim();
    if (url.isEmpty) return;
    final id = 's${DateTime.now().millisecondsSinceEpoch}';
    sessions.add(PhoneSession(
      id: id,
      name: name.trim().isEmpty ? url : name.trim(),
      serverUrl: url,
    ));
    _activeId = id;
    await _save();
    notifyListeners();
  }

  Future<void> select(String id) async {
    if (_activeId == id) return;
    _activeId = id;
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    if (sessions.length <= 1) return;
    sessions.removeWhere((s) => s.id == id);
    if (_activeId == id) _activeId = sessions.first.id;
    await _save();
    notifyListeners();
  }
}