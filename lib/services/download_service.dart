import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class DownloadProgress {
  const DownloadProgress({
    required this.name,
    required this.received,
    required this.total,
    this.path,
    this.error,
    this.done = false,
  });

  final String name;
  final int received;
  final int total;
  final String? path;
  final String? error;
  final bool done;

  double get fraction => total > 0 ? received / total : 0;
}

class EpisodeDownloadService {
  EpisodeDownloadService() : _dio = Dio();

  final Dio _dio;
  final Map<String, CancelToken> _active = {};

  Future<String> download({
    required String url,
    required String fileName,
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.scheme == 'https' || uri.scheme == 'http') ||
        uri.host.isEmpty) {
      throw const FormatException('URL de episódio inválida.');
    }

    final safeName = _safeFileName(fileName);
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory('${directory.path}/AGPlayer/episodios');
    await folder.create(recursive: true);

    final extension = _extensionFromUrl(uri);
    final finalName = safeName.toLowerCase().endsWith(extension)
        ? safeName
        : '$safeName$extension';
    final destination = '${folder.path}/$finalName';
    final token = CancelToken();
    _active[finalName] = token;

    try {
      await _dio.download(
        url,
        destination,
        cancelToken: token,
        deleteOnError: true,
        options: Options(
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
        onReceiveProgress: (received, total) {
          onProgress(DownloadProgress(
            name: finalName,
            received: received,
            total: total,
          ));
        },
      );

      onProgress(DownloadProgress(
        name: finalName,
        received: File(destination).lengthSync(),
        total: File(destination).lengthSync(),
        path: destination,
        done: true,
      ));
      return destination;
    } finally {
      _active.remove(finalName);
    }
  }

  void cancel(String fileName) {
    _active[fileName]?.cancel('Download cancelado pelo usuário.');
  }

  Future<List<FileSystemEntity>> listDownloads() async {
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory('${directory.path}/AGPlayer/episodios');
    if (!await folder.exists()) return const [];
    return folder.list().toList();
  }

  static String _safeFileName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'episodio' : cleaned;
  }

  static String _extensionFromUrl(Uri uri) {
    final path = uri.path.toLowerCase();
    for (final ext in ['.mp4', '.mkv', '.avi', '.mov', '.ts', '.m4v']) {
      if (path.endsWith(ext)) return ext;
    }
    return '.mp4';
  }
}
