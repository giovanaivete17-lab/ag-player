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
    this.url = '',
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
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        type: (j['type'] ?? 'm3u') as String,
        url: (j['url'] ?? '') as String,
        user: (j['user'] ?? '') as String,
        pass: (j['pass'] ?? '') as String,
      );
}

class ProfileStore {
  static const _storage = FlutterSecureStorage();
  static const _kList = 'profiles_v1';
  static const _kActive = 'active_profile_v1';

  static Future<List<Profile>> load() async {
    try {
      final raw = await _storage.read(key: _kList);
      if (raw == null || raw.isEmpty) return <Profile>[];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Profile.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return <Profile>[];
    }
  }

  static Future<void> save(List<Profile> list) async {
    final raw = jsonEncode(list.map((p) => p.toJson()).toList());
    await _storage.write(key: _kList, value: raw);
  }

  static Future<String?> activeId() async {
    try {
      return await _storage.read(key: _kActive);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setActive(String? id) async {
    if (id == null) {
      await _storage.delete(key: _kActive);
    } else {
      await _storage.write(key: _kActive, value: id);
    }
  }
}
