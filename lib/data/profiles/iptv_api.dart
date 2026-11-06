static Future<Catalog> _loadM3u(Profile p, String? cachePath) async {
  String text;

  try {
    if (p.type == 'm3u_file') {
      final file = File(p.url);

      if (!await file.exists()) {
        throw const IptvException(
          'O arquivo M3U não foi encontrado no aparelho.',
        );
      }

      final bytes = await file.readAsBytes();
      text = utf8.decode(bytes, allowMalformed: true);
    } else {
      final res = await _dio.get<String>(
        _fixUrl(p.url),
        options: Options(responseType: ResponseType.plain),
      );

      text = res.data ?? '';
    }
  } on IptvException {
    rethrow;
  } on FileSystemException {
    throw const IptvException(
      'Não foi possível ler o arquivo M3U.',
    );
  }

  if (text.startsWith('\uFEFF')) {
    text = text.substring(1);
  }

  if (!text.contains('#EXTM3U') && !text.contains('#EXTINF')) {
    throw const IptvException(
      'O conteúdo não é uma lista M3U válida.',
    );
  }

  final channels = await M3uParser.parse(text);

  final live = <Item>[];
  final movies = <Item>[];
  final series = <Item>[];

  for (final c in channels) {
    final cat = (c.group == null || c.group!.trim().isEmpty)
        ? 'Sem categoria'
        : c.group!.trim();

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
      logo: c.logo?.trim().isEmpty ?? true ? null : c.logo!.trim(),
      category: cat,
      kind: kind,
    );

    switch (kind) {
      case Kind.live:
        live.add(item);
        break;
      case Kind.movie:
        movies.add(item);
        break;
      case Kind.series:
        series.add(item);
        break;
    }
  }

  if (live.isEmpty && movies.isEmpty && series.isEmpty) {
    throw const IptvException(
      'Nenhum canal ou conteúdo encontrado nessa lista.',
    );
  }

  final catalog = Catalog(
    live: live,
    movies: movies,
    series: series,
  );

  if (cachePath != null) {
    unawaited(
      Isolate.run(
        () => _writeCacheSync(cachePath, catalog, '', ''),
      ).then<void>((_) {}, onError: (_) {}),
    );
  }

  return catalog;
}
