Future<void> _tuneFor(_Media m) async {
  final pl = _player.platform;
  if (pl is! NativePlayer) return;

  final big = _is4k(m);

  try {
    await pl.setProperty(
      'demuxer-max-bytes',
      big ? '48MiB' : '24MiB',
    );

    await pl.setProperty(
      'demuxer-readahead-secs',
      big ? '20' : (m.live ? '8' : '15'),
    );

    await pl.setProperty(
      'framedrop',
      'decoder',
    );
  } catch (_) {}
}
