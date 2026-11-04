import 'dart:convert';
import 'package:dio/dio.dart';
import '../../domain/entities/channel.dart';
import '../parsers/m3u_parser.dart';
import 'profile.dart';

enum Kind { live, movie, series }

class Item {
  final String id;
  final String name;
  final String url; // vazio = série (precisa abrir episódios)
  final String? logo;
  final String category;
  final Kind kind;

  const Item({
    required this.id,
    required this.name,
    required this.url,
    required this.category,
    required this.kind,
    this.logo,
  });
}

class Catalog {
  final List<Item> live;
  final List<Item> movies;
  final List<Item> series;

  const Catalog({
    required this.live,
    required this.movies,
    required this.series,
  });
}

class IptvApi {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 90),
    headers: {'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18'},
  ));

  static String _s(dynamic v) => v == null ? '' : v.toString();

  static String _xBase(String raw) {
    var b = raw.trim();
    if (!b.startsWith('http://') && !b.startsWith('https://')) {
      b = 'http://$b';
    }
    final uri = Uri.parse(b);
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  static Future<Catalog> load(Profile p) async {
    if (p.type == 'xtream') return _loadXtream(p);
    return _loadM3u(p);
  }

  static Future<Catalog> _loadM3u(Profile p) async {
    var u = p.url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    final res = await _dio.get<String>(
      u,
      options: Options(responseType: ResponseType.plain),
    );
    final text = res.data ?? '';
    final List<Channel> channels = await M3uParser.parse(text);

    final live = <Item>[];
    final movies = <Item>[];
    final series = <Item>[];

    for (final c in channels) {
      final String? g = c.group;
      final String? logo = c.logo;
      final cat = (g == null || g.isEmpty) ? 'Sem categoria' : g;
      final lower = c.url.toLowerCase();
      Kind kind = Kind.live;
      if (lower.contains('/movie/')) {
        kind = Kind.movie;
      } else if (lower.contains('/series/')) {
        kind = Kind.series;
      }
      final item = Item(
        id: c.url,
        name: c.name,
        url: c.url,
        logo: (logo == null || logo.isEmpty) ? null : logo,
        category: cat,
        kind: kind,
      );
      if (kind == Kind.movie) {
        movies.add(item);
      } else if (kind == Kind.series) {
        series.add(item);
      } else {
        live.add(item);
      }
    }

    if (live.isEmpty && movies.isEmpty && series.isEmpty) {
      throw Exception('Nenhum canal encontrado nessa lista.');
    }
    return Catalog(live: live, movies: movies, series: series);
  }

  static Future<List<dynamic>> _getList(
    String base,
    Profile p,
    String action, {
    Map<String, String>? extra,
  }) async {
    final res = await _dio.get<dynamic>(
      '$base/player_api.php',
      queryParameters: {
        'username': p.user,
        'password': p.pass,
        'action': action,
        if (extra != null) ...extra,
      },
    );
    final data = res.data;
    if (data is List) return data;
    if (data is String) {
      try {
        final d = jsonDecode(data);
        if (d is List) return d;
      } catch (_) {}
    }
    return <dynamic>[];
  }

  static Map<String, String> _cats(List<dynamic> l) {
    final m = <String, String>{};
    for (final e in l) {
      if (e is Map) {
        m[_s(e['category_id'])] = _s(e['category_name']);
      }
    }
    return m;
  }

  static Future<Catalog> _loadXtream(Profile p) async {
    final base = _xBase(p.url);
    Object? err;

    Future<List<dynamic>> safe(String action) async {
      try {
        return await _getList(base, p, action);
      } catch (e) {
        err ??= e;
        return <dynamic>[];
      }
    }

    final r = await Future.wait([
      safe('get_live_categories'),
      safe('get_vod_categories'),
      safe('get_series_categories'),
      safe('get_live_streams'),
      safe('get_vod_streams'),
      safe('get_series'),
    ]);

    if (r[3].isEmpty && r[4].isEmpty && r[5].isEmpty) {
      final e = err;
      if (e != null) throw e;
      throw Exception(
          'O servidor não retornou nada. Confira endereço, usuário e senha.');
    }

    final liveCats = _cats(r[0]);
    final vodCats = _cats(r[1]);
    final serCats = _cats(r[2]);

    final live = <Item>[];
    for (final e in r[3]) {
      if (e is! Map) continue;
      final id = _s(e['stream_id']);
      final icon = _s(e['stream_icon']);
      live.add(Item(
        id: id,
        name: _s(e['name']),
        url: '$base/live/${p.user}/${p.pass}/$id.ts',
        logo: icon.isEmpty ? null : icon,
        category: liveCats[_s(e['category_id'])] ?? 'Sem categoria',
        kind: Kind.live,
      ));
    }

    final movies = <Item>[];
    for (final e in r[4]) {
      if (e is! Map) continue;
      final id = _s(e['stream_id']);
      final icon = _s(e['stream_icon']);
      var ext = _s(e['container_extension']);
      if (ext.isEmpty) ext = 'mp4';
      movies.add(Item(
        id: id,
        name: _s(e['name']),
        url: '$base/movie/${p.user}/${p.pass}/$id.$ext',
        logo: icon.isEmpty ? null : icon,
        category: vodCats[_s(e['category_id'])] ?? 'Sem categoria',
        kind: Kind.movie,
      ));
    }

    final series = <Item>[];
    for (final e in r[5]) {
      if (e is! Map) continue;
      final cover = _s(e['cover']);
      series.add(Item(
        id: _s(e['series_id']),
        name: _s(e['name']),
        url: '',
        logo: cover.isEmpty ? null : cover,
        category: serCats[_s(e['category_id'])] ?? 'Sem categoria',
        kind: Kind.series,
      ));
    }

    return Catalog(live: live, movies: movies, series: series);
  }

  /// Episódios de uma série Xtream.
  static Future<List<Item>> episodes(Profile p, Item serie) async {
    final base = _xBase(p.url);
    final res = await _dio.get<dynamic>(
      '$base/player_api.php',
      queryParameters: {
        'username': p.user,
        'password': p.pass,
        'action': 'get_series_info',
        'series_id': serie.id,
      },
    );
    dynamic data = res.data;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {}
    }
    final out = <Item>[];
    if (data is! Map) return out;
    final eps = data['episodes'];

    final flat = <dynamic>[];
    if (eps is Map) {
      for (final v in eps.values) {
        if (v is List) flat.addAll(v);
      }
    } else if (eps is List) {
      for (final v in eps) {
        if (v is List) {
          flat.addAll(v);
        } else {
          flat.add(v);
        }
      }
    }

    for (final e in flat) {
      if (e is! Map) continue;
      final id = _s(e['id']);
      var ext = _s(e['container_extension']);
      if (ext.isEmpty) ext = 'mp4';
      final season = _s(e['season']);
      final num = _s(e['episode_num']);
      final title = _s(e['title']);
      out.add(Item(
        id: id,
        name: 'T$season E$num - $title',
        url: '$base/series/${p.user}/${p.pass}/$id.$ext',
        logo: serie.logo,
        category: 'Temporada $season',
        kind: Kind.series,
      ));
    }
    return out;
  }
}
