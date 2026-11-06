Future<void> _configurePlayer() async {
  final pl = _player.platform;
  if (pl is! NativePlayer) return;

  Future<void> set(String k, String v) async {
    try {
      await pl.setProperty(k, v);
    } catch (_) {}
  }

  await set('user-agent', 'VLC/3.0.20 LibVLC/3.0.20');
  await set('tls-verify', 'no');
  await set('network-timeout', '20');
  await set('stream-lavf-o',
      'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');

  await set('cache', 'yes');
  await set('hwdec', 'auto-safe');
  await set('framedrop', 'decoder');
  await set('vd-lavc-fast', 'yes');
  await set('vd-lavc-skiploopfilter', 'nonref');
}
