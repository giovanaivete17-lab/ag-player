import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda o minuto em que você parou cada filme ou episódio.
class ProgressStore {
  static const _storage = FlutterSecureStorage();
  static const _key = 'progress_v1';
  static const _maxItems = 300;

  // url -> [posição em ms, duração em ms, quando salvou em ms]
  static Map<String, List<int>>? _cache;

  static Future<Map<String, List<int>>> _load() async {
    final c = _cache;
    if (c != null) return c;
    final map = <String, List<int>>{};
    try {
      final raw = await _storage.read(key: _key);
      if (raw != null && raw.isNotEmpty) {
        final d = jsonDecode(raw);
        if (d is Map) {
          d.forEach((k, v) {
            if (v is List && v.length >= 3) {
              map[k.toString()] =
                  v.map((e) => (e as num).toInt()).toList();
            }
          });
        }
      }
    } catch (_) {}
    _cache = map;
    return map;
  }

  /// Posição salva para esse link, ou null se não houver.
  static Future<Duration?> position(String url) async {
    if (url.isEmpty) return null;
    final map = await _load();
    final v = map[url];
    if (v == null) return null;
    return Duration(milliseconds: v[0]);
  }

  static Future<void> save(String url, Duration pos, Duration dur) async {
    // Só guarda conteúdo longo (filmes e episódios), nunca canal ao vivo.
    if (url.isEmpty || dur.inSeconds < 300) return;
    final map = await _load();
    final p = pos.inMilliseconds;
    final d = dur.inMilliseconds;

    if (p < 30000 || p > d * 0.95) {
      // começo ou fim: não precisa lembrar
      map.remove(url);
    } else {
      map[url] = [p, d, DateTime.now().millisecondsSinceEpoch];
    }

    if (map.length > _maxItems) {
      final keys = map.keys.toList()
        ..sort((a, b) => map[a]![2].compareTo(map[b]![2]));
      final extra = map.length - _maxItems;
      for (var i = 0; i < extra; i++) {
        map.remove(keys[i]);
      }
    }

    try {
      await _storage.write(key: _key, value: jsonEncode(map));
    } catch (_) {}
  }

  static Future<void> clear() async {
    _cache = <String, List<int>>{};
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}
