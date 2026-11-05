import 'dart:convert';
import 'package:dio/dio.dart';
import 'iptv_api.dart';
import 'profile.dart';

class ItemInfo {
  final String director;
  final String duration;
  final String genre;
  final String cast;
  final String plot;
  final String image;
  final String rating;

  const ItemInfo({
    this.director = '',
    this.duration = '',
    this.genre = '',
    this.cast = '',
    this.plot = '',
    this.image = '',
    this.rating = '',
  });
}

class InfoApi {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 40),
    headers: {'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18'},
  ));

  static final Map<String, ItemInfo> _cache = <String, ItemInfo>{};

  static String _s(dynamic v) => v == null ? '' : v.toString().trim();

  static String _base(String raw) {
    var b = raw.trim();
    if (!b.startsWith('http://') && !b.startsWith('https://')) {
      b = 'http://$b';
    }
    final uri = Uri.parse(b);
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  static String _dur(Map info) {
    final secs = int.tryParse(_s(info['duration_secs']));
    if (secs != null && secs > 0) {
      final h = secs ~/ 3600;
      final m = (secs % 3600) ~/ 60;
      return h > 0 ? '${h}h ${m}m' : '${m}m';
    }
    final mins = int.tryParse(_s(info['episode_run_time']));
    if (mins != null && mins > 0) return '$mins min';
    return _s(info['duration']);
  }

  /// Detalhes de um filme ou série (só listas Xtream). Retorna null se não houver.
  static Future<ItemInfo?> load(Profile p, Item it) async {
    if (p.type != 'xtream') return null;
    if (it.kind == Kind.live || it.id.isEmpty) return null;

    final key = '${p.id}:${it.kind.name}:${it.id}';
    final cached = _cache[key];
    if (cached != null) return cached;

    try {
      final isSerie = it.kind == Kind.series;
      final res = await _dio.get<String>(
        '${_base(p.url)}/player_api.php',
        queryParameters: {
          'username': p.user,
          'password': p.pass,
          'action': isSerie ? 'get_series_info' : 'get_vod_info',
          if (isSerie) 'series_id': it.id else 'vod_id': it.id,
        },
        options: Options(responseType: ResponseType.plain),
      );
      final d = jsonDecode(res.data ?? '');
      if (d is! Map) return null;
      final info = d['info'];
      if (info is! Map) return null;

      var image = _s(info['movie_image']);
      if (image.isEmpty) image = _s(info['cover']);

      var plot = _s(info['plot']);
      if (plot.isEmpty) plot = _s(info['description']);

      var cast = _s(info['cast']);
      if (cast.isEmpty) cast = _s(info['actors']);

      final out = ItemInfo(
        director: _s(info['director']),
        duration: _dur(info),
        genre: _s(info['genre']),
        cast: cast,
        plot: plot,
        image: image,
        rating: _s(info['rating']),
      );
      _cache[key] = out;
      return out;
    } catch (_) {
      return null;
    }
  }
}
