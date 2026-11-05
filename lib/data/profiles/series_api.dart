import 'dart:convert';

import 'package:dio/dio.dart';

import 'profile.dart';

class EpisodeInfo {
  final String title;
  final String url;
  final int season;
  final int number;
  const EpisodeInfo({
    required this.title,
    required this.url,
    required this.season,
    required this.number,
  });
}

class _Creds {
  final String base;
  final String user;
  final String pass;
  const _Creds(this.base, this.user, this.pass);
}

class SeriesApi {
  static const _ua = 'VLC/3.0.20 LibVLC/3.0.20';

  static _Creds? _creds(Profile p) {
    var raw = p.url.trim();
    if (raw.isEmpty) return null;
    if (!raw.startsWith('http')) raw = 'http://$raw';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return null;
    var user = p.user.trim();
    var pass = p.pass.trim();
    if (user.isEmpty) user = uri.queryParameters['username'] ?? '';
    if (pass.isEmpty) pass = uri.queryParameters['password'] ?? '';
    if (user.isEmpty || pass.isEmpty) return null;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return _Creds('${uri.scheme}://${uri.host}$port', user, pass);
  }

  static bool canLoad(Profile p) => _creds(p) != null;

  static Future<List<EpisodeInfo>> load(Profile p, String seriesId) async {
    final c = _creds(p);
    if (c == null) {
      throw Exception('Esta lista não tem usuário e senha.');
    }
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 40),
      responseType: ResponseType.plain,
      headers: {'User-Agent': _ua},
    ));

    String body;
    try {
      final res = await dio.get(
        '${c.base}/player_api.php',
        queryParameters: {
          'username': c.user,
          'password': c.pass,
          'action': 'get_series_info',
          'series_id': seriesId,
        },
      );
      body = res.data.toString();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      throw Exception(code != null
          ? 'O servidor respondeu erro $code.'
          : 'Sem conexão com o servidor.');
    }

    dynamic data;
    try {
      data = jsonDecode(body.trim());
    } catch (_) {
      throw Exception('Resposta inválida do servidor.');
    }
    if (data is! Map) throw Exception('Série sem dados.');

    final eps = data['episodes'];
    final out = <EpisodeInfo>[];
    final u = Uri.encodeComponent(c.user);
    final pw = Uri.encodeComponent(c.pass);

    void addList(dynamic list, int fallbackSeason) {
      if (list is! List) return;
      for (final e in list) {
        if (e is! Map) continue;
        final id = (e['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final ext = (e['container_extension'] ?? 'mp4').toString();
        final season = int.tryParse('${e['season'] ?? ''}') ?? fallbackSeason;
        final n = int.tryParse('${e['episode_num'] ?? ''}') ?? (out.length + 1);
        var title = (e['title'] ?? '').toString().trim();
        if (title.isEmpty) title = 'Episódio $n';
        out.add(EpisodeInfo(
          title: title,
          url: '${c.base}/series/$u/$pw/$id.$ext',
          season: season,
          number: n,
        ));
      }
    }

    if (eps is Map) {
      eps.forEach((k, v) => addList(v, int.tryParse(k.toString()) ?? 1));
    } else if (eps is List) {
      for (var i = 0; i < eps.length; i++) {
        addList(eps[i], i + 1);
      }
    }

    out.sort((a, b) {
      final s = a.season.compareTo(b.season);
      return s != 0 ? s : a.number.compareTo(b.number);
    });
    return out;
  }
}
