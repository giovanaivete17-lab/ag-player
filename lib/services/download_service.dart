import 'dart:async';
import 'dart:io';

class DownloadCancelled implements Exception {
  @override
  String toString() => 'Download cancelado';
}

class DownloadService {
  final Map<String, HttpClient> _clients = {};
  final Set<String> _cancelled = {};

  bool isDownloading(String url) => _clients.containsKey(url);

  /// Baixa [url] para [savePath].
  /// [onProgress] recebe valores de 0.0 a 1.0.
  Future<File> download({
    required String url,
    required String savePath,
    void Function(double progress)? onProgress,
  }) async {
    final client = HttpClient();
    _clients[url] = client;
    _cancelled.remove(url);

    final file = File(savePath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();

    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw HttpException('Erro ${response.statusCode}', uri: Uri.parse(url));
      }

      final total = response.contentLength;
      var received = 0;

      await for (final chunk in response) {
        if (_cancelled.contains(url)) {
          throw DownloadCancelled();
        }
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call(received / total);
        }
      }

      await sink.flush();
      await sink.close();
      onProgress?.call(1.0);
      return file;
    } catch (e) {
      await sink.close();
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    } finally {
      client.close(force: true);
      _clients.remove(url);
      _cancelled.remove(url);
    }
  }

  void cancel(String url) {
    if (_clients.containsKey(url)) {
      _cancelled.add(url);
      _clients[url]?.close(force: true);
    }
  }

  void cancelAll() {
    for (final url in _clients.keys.toList()) {
      cancel(url);
    }
  }
}
