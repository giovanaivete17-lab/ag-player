import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'iptv_api.dart';

/// Guarda os favoritos de cada lista (perfil).
class FavoritesStore {
  static const _storage = FlutterSecureStorage();

  /// Muda toda vez que um favorito é adicionado ou removido.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static final Map<String, Map<String, Item>> _cache =
      <String, Map<String, Item>>{};

  static String _key(String pid) => 'favorites_v1_$pid';
  static String _k(Item i) => '${i.kind.name}:${i.id}';

  static Future<Map<String, Item>> _load(String pid) async {
    final c = _cache[pid];
    if (c != null) return c;
    final map = <String, Item>{};
    try {
      final raw = await _storage.read(key: _key(pid));
      if (raw != null && raw.isNotEmpty) {
        final d = jsonDecode(raw);
        if (d is List) {
          for (final e in d) {
            if (e is! Map) continue;
            final kindName = (e['kind'] ?? 'live').toString();
            final kind = Kind.values.firstWhere(
              (k) => k.name == kindName,
              orElse: () => Kind.live,
            );
            final logo = (e['logo'] ?? '').toString();
            final it = Item(
              id: (e['id'] ?? '').toString(),
              name: (e['name'] ?? '').toString(),
              url: (e['url'] ?? '').toString(),
              category: (e['category'] ?? '').toString(),
              kind: kind,
              logo: logo.isEmpty ? null : logo,
            );
            map[_k(it)] = it;
          }
        }
      }
    } catch (_) {}
    _cache[pid] = map;
    return map;
  }

  static Future<void> _save(String pid) async {
    final map = _cache[pid];
    if (map == null) return;
    final list = map.values
        .map((i) => {
              'id': i.id,
              'name': i.name,
              'url': i.url,
              'logo': i.logo ?? '',
              'category': i.category,
              'kind': i.kind.name,
            })
        .toList();
    try {
      await _storage.write(key: _key(pid), value: jsonEncode(list));
    } catch (_) {}
  }

  /// Carrega os favoritos na memória (chamar ao abrir a lista).
  static Future<void> preload(String pid) async {
    await _load(pid);
    changes.value++;
  }

  /// Verifica na memória se o item é favorito.
  static bool has(String pid, Item it) {
    final m = _cache[pid];
    if (m == null) return false;
    return m.containsKey(_k(it));
  }

  static int count(String pid) => _cache[pid]?.length ?? 0;

  static Future<List<Item>> all(String pid, {Kind? kind}) async {
    final m = await _load(pid);
    final l = m.values.where((i) => kind == null || i.kind == kind).toList();
    l.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return l;
  }

  static Future<void> toggle(String pid, Item it) async {
    final m = await _load(pid);
    final k = _k(it);
    if (m.containsKey(k)) {
      m.remove(k);
    } else {
      m[k] = it;
    }
    await _save(pid);
    changes.value++;
  }
}
