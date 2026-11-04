import 'package:media_kit/media_kit.dart';

class PlayerService {
  PlayerService() : player = Player();

  final Player player;

  Future<void> play(String url) async {
    await player.open(Media(url), play: true);
  }

  Future<void> pause() => player.pause();
  Future<void> resume() => player.play();
  Future<void> stop() => player.stop();

  Future<void> setAspect(String mode) async {
    final value = switch (mode) {
      '4:3' => '4:3',
      '16:9' => '16:9',
      _ => '-1',
    };
    final platform = player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('video-aspect-override', value);
    }
  }

  Future<void> dispose() => player.dispose();
}
