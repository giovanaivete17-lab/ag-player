import 'package:media_kit/media_kit.dart';

/// Ajustes do player para aparelhos fracos e canais 4K.
class PlayerTuning {
  static Future<void> apply(Player player, {bool leve = true}) async {
    final p = player.platform;
    if (p is! NativePlayer) return;
    final opts = <String, String>{
      'cache': 'yes',
      'demuxer-max-bytes': leve ? '16MiB' : '48MiB',
      'demuxer-max-back-bytes': '4MiB',
      'demuxer-readahead-secs': leve ? '10' : '30',
      'vd-lavc-fast': 'yes',
      'vd-lavc-skiploopfilter': 'nonref',
      'framedrop': 'vo',
      'network-timeout': '20',
    };
    for (final e in opts.entries) {
      try {
        await p.setProperty(e.key, e.value);
      } catch (_) {}
    }
  }
}
