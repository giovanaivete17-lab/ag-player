import 'dart:convert';
import 'dart:isolate';
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

class IptvException implements Exception {
  final String message;
  const IptvException(this.message);

  @override
  String toString() => message;
}

class IptvApi {
  /// Formato do canal ao vivo: 'ts' ou 'm3u8'.
  static String liveExt = 'ts';

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 25),
    receiveTimeout: const Duration(seconds: 120),
    headers: {'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18'},
  ));

  static String _s(dynamic v) => v == null ? '' : v.toString().trim();

  static String _fixUrl(String raw) {
    var b = raw.trim();
    if (!b.startsWith('http://') && !b.startsWith('https://')) {
      b = 'http://$b';
    }
    return b;
  }

  static String _xBase(String raw) {
    final uri = Uri.parse(_fixUrl(raw));
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  static String _dioMsg(DioException e) {
    final code = e.response?.statusCode;
    if (code != null) {
      return 'O servidor recusou o acesso (código $code). '
          'Confira endereço, usuário e senha.';
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'O servidor demorou demais para responder. Tente de novo.';
      case DioExceptionType.connectionError:
        return 'Sem conexão com o servidor. Confira o endereço e a internet.';
      default:
        return 'Falha ao acessar o servidor. Confira o endereço.';
    }
  }

  static Future<dynamic> _decode(String text) async {
    final t = text.trim();
    if (t.isEmpty) return null;
    try {
      return await Isolate.run(() => jsonDecode(t));
    } catch (_) {
      return null;
    }
  }

  static Future<Catalog> load(Profile p) async {
    try {
      if (p.type == 'xtream') return await _loadXtream(p);

      // Link M3U do tipo get.php?username=..&password=.. -> tenta como Xtream
      try {
        final uri = Uri.parse(_fixUrl(p.url));
        final u = uri.queryParameters['username'];
        final pw = uri.queryParameters['password'];
        if (uri.path.contains('get.php') &&
            u != null &&
            u.isNotEmpty &&
            pw != null &&
            pw.isNotEmpty) {
          final x = Profile(
            id: p.id,
            name: p.name,
            type: 'xtream',
            url: _xBase(p.url),
            user: u,
            pass: pw,
          );
          try {
            return await _loadXtream(x);
          } catch (_) {
            // cai para a leitura normal do M3U
          }
        }
      } catch (_) {}

      return await _loadM3u(p);
    } on DioException catch (e) {
      throw IptvException(_dioMsg(e));
    }
  }

  // ---------------- M3U ----------------

  static bool _isVodFile(String url) {
    final path = url.toLowerCase().split('?').first;
    return path.endsWith('.mp4') ||
        path.endsWith('.mkv') ||
        path.endsWith('.avi') ||
        path.endsWith('.mov') ||
        path.endsWith('.wmv') ||
        path.endsWith('.flv');
  }

  static Future<Catalog> _loadM3u(Profile p) async {
    final res = await _dio.get<String>(
      _fixUrl(p.url),
      options: Options(responseType: ResponseType.plain),
    );
    var text = res.data ?? '';
    if (text.startsWith('\uFEFF')) text = text.substring(1);

    if (!text.contains('#EXTM3U') && !text.contains('#EXTINF')) {
      throw const IptvException(
          'O link não retornou uma lista M3U válida. Confira o endereço.');
    }

    final List<Channel> channels = await M3uParser.parse(text);

    final live = <Item>[];
    final movies = <Item>[];
    final series = <Item>[];

    for (final c in channels) {
      final String? g = c.group;
      final String? logo = c.logo;
      final cat = (g == null || g.trim().isEmpty) ? 'Sem categoria' : g.trim();
      final lowerUrl = c.url.toLowerCase();
      final lowerCat = cat.toLowerCase();

      Kind kind = Kind.live;
      if (lowerUrl.contains('/movie/')) {
        kind = Kind.movie;
      } else if (lowerUrl.contains('/series/')) {
        kind = Kind.series;
      } else if (_isVodFile(c.url)) {
        final isSerie = lowerCat.contains('serie') ||
            lowerCat.contains('séri') ||
            lowerCat.contains('season') ||
            lowerCat.contains('temporada');
        kind = isSerie ? Kind.series : Kind.movie;
      }

      final item = Item(
        id: c.url,
        name: c.name.trim(),
        url: c.url,
        logo: (logo == null || logo.trim().isEmpty) ? null : logo.trim(),
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
      throw const IptvException('Nenhum canal encontrado nessa lista.');
    }
    return Catalog(live: live, movies: movies, series: series);
  }

  // ---------------- Xtream ----------------

  static Future<void> _auth(String base, Profile p) async {
    dynamic data;
    try {
      final res = await _dio.get<String>(
        '$base/player_api.php',
        queryParameters: {'username': p.user, 'password': p.pass},
        options: Options(responseType: ResponseType.plain),
      );
      data = await _decode(res.data ?? '');
    } on DioException {
      return;
    }
    if (data is Map) {
      final ui = data['user_info'];
      if (ui is Map) {
        if (_s(ui['auth']) == '0') {
          throw const IptvException('Usuário ou senha inválidos.');
        }
        final st = _s(ui['status']);
        if (st.isNotEmpty && st.toLowerCase() != 'active') {
          throw IptvException('Conta $st. Fale com seu fornecedor.');
        }
      }
    }
  }

  static Future<List<dynamic>> _getList(
    String base,
    Profile p,
    String action,
  ) async {
    final res = await _dio.get<String>(
      '$base/player_api.php',
      queryParameters: {
        'username': p.user,
        'password': p.pass,
        'action': action,
      },
      options: Options(responseType: ResponseType.plain),
    );
    final data = await _decode(res.data ?? '');
    if (data is List) return data;
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

  static String _catName(Map<String, String> cats, dynamic id) {
    final n = cats[_s(id)];
    return (n == null || n.isEmpty) ? 'Sem categoria' : n;
  }

  static Future<Catalog> _loadXtream(Profile p) async {
    final base = _xBase(p.url);
    await _auth(base, p);

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
      throw const IptvException(
          'O servidor não retornou canais. Confira endereço, usuário e senha.');
    }

    final liveCats = _cats(r[0]);
    final vodCats = _cats(r[1]);
    final serCats = _cats(r[2]);

    final live = <Item>[];
    for (final e in r[3]) {
      if (e is! Map) continue;
      final id = _s(e['stream_id']);
      if (id.isEmpty) continue;
      final icon = _s(e['stream_icon']);
      live.add(Item(
        id: id,
        name: _s(e['name']),
        url: '$base/live/${p.user}/${p.pass}/$id.$liveExt',
        logo: icon.isEmpty ? null : icon,
        category: _catName(liveCats, e['category_id']),
        kind: Kind.live,
      ));
    }

    final movies = <Item>[];
    for (final e in r[4]) {
      if (e is! Map) continue;
      final id = _s(e['stream_id']);
      if (id.isEmpty) continue;
      final icon = _s(e['stream_icon']);
      var ext = _s(e['container_extension']);
      if (ext.isEmpty) ext = 'mp4';
      movies.add(Item(
        id: id,
        name: _s(e['name']),
        url: '$base/movie/${p.user}/${p.pass}/$id.$ext',
        logo: icon.isEmpty ? null : icon,
        category: _catName(vodCats, e['category_id']),
        kind: Kind.movie,
      ));
    }

    final series = <Item>[];
    for (final e in r[5]) {
      if (e is! Map) continue;
      final id = _s(e['series_id']);
      if (id.isEmpty) continue;
      final cover = _s(e['cover']);
      series.add(Item(
        id: id,
        name: _s(e['name']),
        url: '',
        logo: cover.isEmpty ? null : cover,
        category: _catName(serCats, e['category_id']),
        kind: Kind.series,
      ));
    }

    return Catalog(live: live, movies: movies, series: series);
  }

  /// Episódios de uma série Xtream.
  static Future<List<Item>> episodes(Profile p, Item serie) async {
    final base = _xBase(p.url);
    final res = await _dio.get<String>(
      '$base/player_api.php',
      queryParameters: {
        'username': p.user,
        'password': p.pass,
        'action': 'get_series_info',
        'series_id': serie.id,
      },
      options: Options(responseType: ResponseType.plain),
    );
    final data = await _decode(res.data ?? '');
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
      if (id.isEmpty) continue;
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
