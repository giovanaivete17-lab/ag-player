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
  final String year;

  const ItemInfo({
    this.director = '',
    this.duration = '',
    this.genre = '',
    this.cast = '',
    this.plot = '',
    this.image = '',
    this.rating = '',
    this.year = '',
  });
}

class InfoApi {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 40),
      headers: {
        'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
      },
    ),
  );

  static final Map<String, ItemInfo> _cache = {};

  static String _s(dynamic value) {
    return value == null ? '' : value.toString().trim();
  }

  static String _base(String raw) {
    var value = raw.trim();

    if (!value.startsWith('http://') &&
        !value.startsWith('https://')) {
      value = 'http://$value';
    }

    final uri = Uri.parse(value);
    final port = uri.hasPort ? ':${uri.port}' : '';

    return '${uri.scheme}://${uri.host}$port';
  }

  static Map<String, String> _credentials(Profile profile) {
    var username = profile.user.trim();
    var password = profile.pass.trim();

    if (username.isEmpty || password.isEmpty) {
      try {
        final uri = Uri.parse(profile.url);

        username = username.isEmpty
            ? (uri.queryParameters['username'] ?? '')
            : username;

        password = password.isEmpty
            ? (uri.queryParameters['password'] ?? '')
            : password;
      } catch (_) {}
    }

    return {
      'username': username,
      'password': password,
    };
  }

  static String _duration(Map info) {
    final seconds = int.tryParse(_s(info['duration_secs']));

    if (seconds != null && seconds > 0) {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;

      return hours > 0
          ? '${hours}h ${minutes}min'
          : '${minutes}min';
    }

    final runtime = int.tryParse(
      _s(info['episode_run_time']),
    );

    if (runtime != null && runtime > 0) {
      return '$runtime min';
    }

    return _s(info['duration']);
  }

  static String _year(Map info) {
    final date = _s(info['releasedate']).isNotEmpty
        ? _s(info['releasedate'])
        : _s(info['release_date']);

    if (date.length >= 4) {
      final match = RegExp(r'\d{4}').firstMatch(date);

      if (match != null) {
        return match.group(0) ?? '';
      }
    }

    final year = _s(info['year']);

    if (RegExp(r'^\d{4}$').hasMatch(year)) {
      return year;
    }

    return '';
  }

  /// Busca os detalhes de filmes e séries no servidor Xtream.
  /// Retorna null quando o servidor não fornece informações.
  static Future<ItemInfo?> load(Profile profile, Item item) async {
    if (item.kind == Kind.live || item.id.isEmpty) {
      return null;
    }

    final credentials = _credentials(profile);
    final username = credentials['username'] ?? '';
    final password = credentials['password'] ?? '';

    if (username.isEmpty || password.isEmpty) {
      return null;
    }

    // O identificador precisa ser numérico para consultar
    // get_vod_info ou get_series_info no Xtream.
    if (int.tryParse(item.id) == null) {
      return null;
    }

    final key = '${profile.id}:${item.kind.name}:${item.id}';

    final cached = _cache[key];

    if (cached != null) {
      return cached;
    }

    try {
      final isSeries = item.kind == Kind.series;

      final response = await _dio.get<String>(
        '${_base(profile.url)}/player_api.php',
        queryParameters: {
          'username': username,
          'password': password,
          'action': isSeries
              ? 'get_series_info'
              : 'get_vod_info',
          if (isSeries)
            'series_id': item.id
          else
            'vod_id': item.id,
        },
        options: Options(
          responseType: ResponseType.plain,
        ),
      );

      final body = response.data ?? '';

      if (body.isEmpty) {
        return null;
      }

      final decoded = jsonDecode(body);

      if (decoded is! Map) {
        return null;
      }

      final info = decoded['info'];

      if (info is! Map) {
        return null;
      }

      var image = _s(info['movie_image']);

      if (image.isEmpty) {
        image = _s(info['cover_big']);
      }

      if (image.isEmpty) {
        image = _s(info['cover']);
      }

      var plot = _s(info['plot']);

      if (plot.isEmpty) {
        plot = _s(info['description']);
      }

      var cast = _s(info['cast']);

      if (cast.isEmpty) {
        cast = _s(info['actors']);
      }

      final result = ItemInfo(
        director: _s(info['director']),
        duration: _duration(info),
        genre: _s(info['genre']),
        cast: cast,
        plot: plot,
        image: image,
        rating: _s(info['rating']),
        year: _year(info),
      );

      _cache[key] = result;

      return result;
    } catch (_) {
      return null;
    }
  }

  static void clearCache() {
    _cache.clear();
  }
}
