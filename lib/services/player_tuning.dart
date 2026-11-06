
import 'package:media_kit/media_kit.dart';

/// Configurações adaptáveis para melhorar o carregamento
/// de áudio e vídeo em diferentes aparelhos.
class PlayerTuning {
  static Future<void> apply(
    Player player, {
    bool leve = true,
  }) async {
    final platform = player.platform;

    if (platform is! NativePlayer) return;

    final options = <String, String>{
      'cache': 'yes',
      'demuxer-max-bytes': leve ? '16MiB' : '48MiB',
      'demuxer-max-back-bytes': '4MiB',
      'demuxer-readahead-secs': leve ? '10' : '20',
      'vd-lavc-fast': 'yes',
      'framedrop': 'vo',
      'network-timeout': '20',
    };

    for (final option in options.entries) {
      try {
        await platform.setProperty(
          option.key,
          option.value,
        );
      } catch (_) {
        // Mantém compatibilidade com aparelhos
        // que não aceitam determinada configuração.
      }
    }
  }
}
