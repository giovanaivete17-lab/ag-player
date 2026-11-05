import 'dart:convert';

import 'package:dio/dio.dart';

import 'profile.dart';

class EpgEntry {
  final String title;
  final String description;
  final DateTime start;
  final DateTime stop;
  const EpgEntry({
    required this.title,
    required this.description,
    required this.start,
    required this.stop,
  });
}

class _C {
  final String base;
  final String user;
  final String pass;
  const _C(this.base, this.user, this.pass);
}

class EpgApi {
  static const _ua = 'VLC/3.0.20 LibVLC/3.0.20';
  static final Map<String, List<EpgEntry>> _cache = {};
  static final Map<String, DateTime> _cacheAt = {};

  static _C? _creds(Profile p) {
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
    return _C('${uri.scheme}://${uri.host}$port', user, pass);
  }

  static bool canLoad(Profile p) => _creds(p) != null;

  // Pega o número do canal no final do link (…/123.ts)
  static String? streamIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.pathSegments.isEmpty) return null;
    var last = uri.pathSegments.last;
    final dot = last.lastIndexOf('.');
    if (dot > 0) last = last.substring(0, dot);
    return int.tryParse(last) != null ? last : null;
  }

  static String _b64(dynamic v) {
    final s = (v ?? '').toString();
    if (s.isEmpty) return '';
    try {
      final d = utf8.decode(base64.decode(base64.normalize(s)),
          allowMalformed: true);
      if (d.contains('\uFFFD')) return s;
      return d.trim();
    } catch (_) {
      return s;
    }
  }

  static DateTime? _time(dynamic ts, dynamic text) {
    final n = int.tryParse('${ts ?? ''}');
    if (n != null && n > 0) {
      return DateTime.fromMillisecondsSinceEpoch(n * 1000);
    }
    final t = (text ?? '').toString().trim();
    if (t.isEmpty) return null;
    return DateTime.tryParse(t.replaceFirst(' ', 'T'));
  }

  static Future<List<EpgEntry>> load(Profile p, String streamId) async {
    final c = _creds(p);
    if (c == null) return [];
    final key = '${c.base}|${c.user}|$streamId';
    final at = _cacheAt[key];
    if (at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 5)) {
      return _cache[key] ?? [];
    }
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
        responseType: ResponseType.plain,
        headers: {'User-Agent': _ua},
      ));
      final res = await dio.get(
        '${c.base}/player_api.php',
        queryParameters: {
          'username': c.user,
          'password': c.pass,
          'action': 'get_short_epg',
          'stream_id': streamId,
          'limit': '6',
        },
      );
      final data = jsonDecode(res.data.toString().trim());
      final list = data is Map ? data['epg_listings'] : null;
      final out = <EpgEntry>[];
      if (list is List) {
        for (final e in list) {
          if (e is! Map) continue;
          final s = _time(e['start_timestamp'], e['start']);
          final f = _time(e['stop_timestamp'], e['end']);
          if (s == null || f == null) continue;
          final title = _b64(e['title']);
          if (title.isEmpty) continue;
          out.add(EpgEntry(
            title: title,
            description: _b64(e['description']),
            start: s,
            stop: f,
          ));
        }
      }
      out.sort((a, b) => a.start.compareTo(b.start));
      _cache[key] = out;
      _cacheAt[key] = DateTime.now();
      return out;
    } catch (_) {
      return [];
    }
  }
}
