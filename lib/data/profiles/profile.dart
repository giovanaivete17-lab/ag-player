import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Profile {
  final String id;
  final String name;
  final String type; // 'm3u' ou 'xtream'
  final String url;
  final String user;
  final String pass;

  const Profile({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
    this.user = '',
    this.pass = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'url': url,
        'user': user,
        'pass': pass,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        type: (j['type'] ?? 'm3u').toString(),
        url: (j['url'] ?? '').toString(),
        user: (j['user'] ?? '').toString(),
        pass: (j['pass'] ?? '').toString(),
      );
}

class ProfileStore {
  static const _s = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kList = 'ag_profiles_v1';
  static const _kActive = 'ag_active_profile_v1';

  static List<Profile>? _cache;
  static String? _active;

  static Future<List<Profile>> load() async {
    if (_cache != null) return List<Profile>.from(_cache!);
    try {
      final raw = await _s.read(key: _kList);
      if (raw == null || raw.isEmpty) {
        _cache = [];
      } else {
        final data = jsonDecode(raw) as List;
        _cache = data
            .map((e) => Profile.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {
      _cache = [];
    }
    return List<Profile>.from(_cache!);
  }

  // Grava e confere se gravou mesmo. Se falhar, lança erro com o motivo.
  static Future<void> save(List<Profile> list) async {
    final json = jsonEncode(list.map((p) => p.toJson()).toList());
    await _s.write(key: _kList, value: json);
    final check = await _s.read(key: _kList);
    if (check != json) {
      throw Exception('o aparelho não gravou os dados');
    }
    _cache = List<Profile>.from(list);
  }

  static Future<String?> activeId() async {
    if (_active != null) return _active;
    try {
      _active = await _s.read(key: _kActive);
    } catch (_) {}
    return _active;
  }

  static Future<void> setActive(String id) async {
    _active = id;
    try {
      await _s.write(key: _kActive, value: id);
    } catch (_) {}
  }
}
