import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
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

// ---------- Cache em disco (roda em segundo plano) ----------

String _strip(String url, String user, String pass) {
  if (user.isEmpty || pass.isEmpty) return url;
  return url.replaceFirst('/$user/$pass/', '/{U}/');
}

String _unstrip(String url, String user, String pass) {
  if (user.isEmpty || pass.isEmpty) return url;
  return url.replaceFirst('/{U}/', '/$user/$pass/');
}

List<List<String>> _encItems(List<Item> l, String user, String pass) {
  return [
    for (final i in l)
      [i.id, i.name, _strip(i.url, user, pass), i.logo ?? '', i.category],
  ];
}

List<Item> _decItems(dynamic l, Kind k, String user, String pass) {
  final out = <Item>[];
  if (l is! List) return out;
  for (final e in l) {
    if (e is! List || e.length < 5) continue;
    final logo = e[3] as String;
    out.add(Item(
      id: e[0] as String,
      name: e[1] as String,
      url: _unstrip(e[2] as String, user, pass),
      logo: logo.isEmpty ? null : logo,
      category: e[4] as String,
      kind: k,
    ));
  }
  return out;
}

void _writeCacheSync(String path, Catalog c, String user, String pass) {
  try {
    final data = jsonEncode({
      'v': 1,
      'x': (user.isNotEmpty && pass.isNotEmpty) ? 1 : 0,
      'l': _encItems(c.live, user, pass),
      'm': _encItems(c.movies, user, pass),
      's': _encItems(c.series, user, pass),
    });
    final tmp = File('$path.tmp');
    tmp.writeAsStringSync(data, flush: true);
    tmp.renameSync(path);
  } catch (_) {}
}

class _CacheReq {
  final String path;
  final String user;
  final String pass;
  const _CacheReq(this.path, this.user, this.pass);
}

class _CacheRead {
  final Catalog catalog;
  final int ageMin;
  const _CacheRead(this.catalog, this.ageMin);
}

_CacheRead? _readCacheSync(_CacheReq r) {
  try {
    final f = File(r.path);
    if (!f.existsSync()) return null;
    final age = DateTime.now().difference(f.lastModifiedSync()).inMinutes;
    final j = jsonDecode(f.readAsStringSync());
    if (j is! Map || j['v'] != 1) return null;
    final u = j['x'] == 1 ? r.user : '';
    final p = j['x'] == 1 ? r.pass : '';
    final live = _decItems(j['l'], Kind.live, u, p);
    final movies = _decItems(j['m'], Kind.movie, u, p);
    final series = _decItems(j['s'], Kind.series, u, p);
    if (live.isEmpty && movies.isEmpty && series.isEmpty) return null;
    return _CacheRead(
        Catalog(live: live, movies: movies, series: series), age);
  } catch (_) {
    return null;
  }
}

// ---------- Leitura Xtream (roda em segundo plano) ----------

class _XIn {
  final String base;
  final String user;
  final String pass;
  final String ext;
  final String cachePath;
  final List<TransferableTypedData> raw;
  const _XIn({
    required this.base,
    required this.user,
    required this.pass,
    required this.ext,
    required this.cachePath,
    required this.raw,
  });
}

Catalog _buildXtream(_XIn a) {
  List<dynamic> dec(int i) {
    try {
      final bytes = a.raw[i].materialize().asUint8List();
      if (bytes.isEmpty) return const <dynamic>[];
      final v = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      return v is List ? v : const <dynamic>[];
    } catch (_) {
      return const <dynamic>[];
    }
  }

  String s(dynamic v) => v == null ? '' : v.toString().trim();

  Map<String, String> cats(List<dynamic> l) {
    final m = <String, String>{};
    for (final e in l) {
      if (e is Map) m[s(e['category_id'])] = s(e['category_name']);
    }
    return m;
  }

  String catName(Map<String, String> m, dynamic id) {
    final n = m[s(id)];
    return (n == null || n.isEmpty) ? 'Sem categoria' : n;
  }

  final liveCats = cats(dec(0));
  final vodCats = cats(dec(1));
  final serCats = cats(dec(2));

  final live = <Item>[];
  for (final e in dec(3)) {
    if (e is! Map) continue;
    final id = s(e['stream_id']);
    if (id.isEmpty) continue;
    final icon = s(e['stream_icon']);
    live.add(Item(
      id: id,
      name: s(e['name']),
      url: '${a.base}/live/${a.user}/${a.pass}/$id.${a.ext}',
      logo: icon.isEmpty ? null : icon,
      category: catName(liveCats, e['category_id']),
      kind: Kind.live,
    ));
  }

  final movies = <Item>[];
  for (final e in dec(4)) {
    if (e is! Map) continue;
    final id = s(e['stream_id']);
    if (id.isEmpty) continue;
    final icon = s(e['stream_icon']);
    var ext = s(e['container_extension']);
    if (ext.isEmpty) ext = 'mp4';
    movies.add(Item(
      id: id,
      name: s(e['name']),
      url: '${a.base}/movie/${a.user}/${a.pass}/$id.$ext',
      logo: icon.isEmpty ? null : icon,
      category: catName(vodCats, e['category_id']),
      kind: Kind.movie,
    ));
  }

  final series = <Item>[];
  for (final e in dec(5)) {
    if (e is! Map) continue;
    final id = s(e['series_id']);
    if (id.isEmpty) continue;
    final cover = s(e['cover']);
    series.add(Item(
      id: id,
      name: s(e['name']),
      url: '',
      logo: cover.isEmpty ? null : cover,
      category: catName(serCats, e['category_id']),
      kind: Kind.series,
    ));
  }

  final cat = Catalog(live: live, movies: movies, series: series);
  if (a.cachePath.isNotEmpty &&
      (live.isNotEmpty || movies.isNotEmpty || series.isNotEmpty)) {
    _writeCacheSync(a.cachePath, cat, a.user, a.pass);
  }
  return cat;
}

class IptvApi {
  /// Servidor fixo do app.
  static const String defaultServer = 'http://alphafantasma.top';

  /// Atualiza a lista em segundo plano depois de tantos minutos.
  static const int cacheTtlMin = 360;

  /// Formato do canal ao vivo: 'ts' ou 'm3u8'.
  static String liveExt = 'ts';

  static final Set<String> _busy = <String>{};

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 25),
    receiveTimeout: const Duration(seconds: 120),
    headers: {'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18'},
  ));

  static String _s(dynamic v) => v == null ? '' : v.toString().trim();
  static String _n(dynamic v) => v == null ? '' : v.toString();

  static String _fixUrl(String raw) {
    var b = raw.trim();
    if (!b.startsWith('http://') && !b.startsWith('https://')) {
      b = 'http://$b';
    }
    return b;
  }

  static String _xBase(String raw) {
    final r = raw.trim();
    final uri = Uri.parse(_fixUrl(r.isEmpty ? defaultServer : r));
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

  static String _fnv(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }

  static String? _cachePath(Profile p) {
    try {
      final key = _fnv(
          '${p.type}|${p.url}|${_n(p.user)}|${_n(p.pass)}|$liveExt');
      return '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'agplayer_$key.json';
    } catch (_) {
      return null;
    }
  }

  /// Link get.php?username=..&password=.. vira perfil Xtream.
  static Profile _effective(Profile p) {
    if (p.type == 'xtream') return p;
    try {
      final uri = Uri.parse(_fixUrl(p.url));
      final u = uri.queryParameters['username'];
      final pw = uri.queryParameters['password'];
      if (uri.path.contains('get.php') &&
          u != null &&
          u.isNotEmpty &&
          pw != null &&
          pw.isNotEmpty) {
        return Profile(
          id: p.id,
          name: p.name,
          type: 'xtream',
          url: _xBase(p.url),
          user: u,
          pass: pw,
        );
      }
    } catch (_) {}
    return p;
  }

  /// Abre a lista. Se já existe uma cópia no aparelho, devolve na hora e
  /// atualiza em segundo plano (chama [onFresh] quando terminar).
  static Future<Catalog> load(
    Profile p, {
    void Function(Catalog)? onFresh,
  }) async {
    final path = _cachePath(p);
    if (path != null) {
      final eff = _effective(p);
      final req = _CacheReq(path, _n(eff.user), _n(eff.pass));
      _CacheRead? cached;
      try {
        cached = await Isolate.run(() => _readCacheSync(req));
      } catch (_) {
        cached = null;
      }
      if (cached != null) {
        if (cached.ageMin >= cacheTtlMin) _refresh(p, path, onFresh);
        return cached.catalog;
      }
    }
    return _fetch(p, path);
  }

  static void _refresh(
    Profile p,
    String path,
    void Function(Catalog)? onFresh,
  ) {
    if (_busy.contains(path)) return;
    _busy.add(path);
    () async {
      try {
        final c = await _fetch(p, path);
        onFresh?.call(c);
      } catch (_) {
        // sem internet agora: continua com a cópia antiga
      } finally {
        _busy.remove(path);
      }
    }();
  }

  static Future<Catalog> _fetch(Profile p, String? cachePath) async {
    try {
      final eff = _effective(p);
      if (eff.type == 'xtream') {
        if (identical(eff, p)) return await _loadXtream(eff, cachePath);
        try {
          return await _loadXtream(eff, cachePath);
        } catch (_) {
          // cai para a leitura normal do M3U
        }
      }
      return await _loadM3u(p, cachePath);
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

  static Future<Catalog> _loadM3u(Profile p, String? cachePath) async {
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
    final cat = Catalog(live: live, movies: movies, series: series);
    if (cachePath != null) {
      unawaited(Isolate.run(() => _writeCacheSync(cachePath, cat, '', ''))
          .then<void>((_) {}, onError: (_) {}));
    }
    return cat;
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

  static Future<Uint8List> _getBytes(
    String base,
    Profile p,
    String action,
  ) async {
    final res = await _dio.get<List<int>>(
      '$base/player_api.php',
      queryParameters: {
        'username': p.user,
        'password': p.pass,
        'action': action,
      },
      options: Options(responseType: ResponseType.bytes),
    );
    final d = res.data;
    if (d == null) return Uint8List(0);
    return d is Uint8List ? d : Uint8List.fromList(d);
  }

  static Future<Catalog> _loadXtream(Profile p, String? cachePath) async {
    final base = _xBase(p.url);
    await _auth(base, p);

    Object? err;

    Future<Uint8List> safe(String action) async {
      try {
        return await _getBytes(base, p, action);
      } catch (e) {
        err ??= e;
        return Uint8List(0);
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

    final input = _XIn(
      base: base,
      user: _n(p.user),
      pass: _n(p.pass),
      ext: liveExt,
      cachePath: cachePath ?? '',
      raw: [for (final b in r) TransferableTypedData.fromList([b])],
    );
    final cat = await Isolate.run(() => _buildXtream(input));

    if (cat.live.isEmpty && cat.movies.isEmpty && cat.series.isEmpty) {
      final e = err;
      if (e != null) throw e;
      throw const IptvException(
          'O servidor não retornou canais. Confira endereço, usuário e senha.');
    }
    return cat;
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
