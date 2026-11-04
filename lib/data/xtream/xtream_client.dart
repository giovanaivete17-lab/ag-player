import 'package:dio/dio.dart';

class XtreamClient {
  XtreamClient({
    required String host,
    required String username,
    required String password,
  }) : _dio = Dio(BaseOptions(
          baseUrl: '${host.trim().replaceAll(RegExp(r'/+$'), '')}/',
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          queryParameters: {'username': username, 'password': password},
          responseType: ResponseType.json,
        ));

  final Dio _dio;

  Future<Map<String, dynamic>> authenticate() async {
    final response = await _dio.get('player_api.php');
    if (response.data is! Map) {
      throw const FormatException('Resposta de autenticação inválida.');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    final userInfo = data['user_info'];
    if (userInfo is Map && userInfo['auth']?.toString() == '0') {
      throw const FormatException('Usuário ou senha não reconhecidos.');
    }
    return data;
  }

  Future<List<dynamic>> liveStreams() => _list('get_live_streams');
  Future<List<dynamic>> liveCategories() => _list('get_live_categories');
  Future<List<dynamic>> vodStreams() => _list('get_vod_streams');
  Future<List<dynamic>> series() => _list('get_series');

  Future<List<dynamic>> _list(String action) async {
    final response = await _dio.get(
      'player_api.php',
      queryParameters: {'action': action},
    );
    if (response.data is! List) return const [];
    return List<dynamic>.from(response.data as List);
  }
}
