import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/profiles/epg_api.dart';
import '../../data/profiles/favorites_store.dart';
import '../../data/profiles/iptv_api.dart';
import '../../data/profiles/profile.dart';
import '../../data/profiles/progress_store.dart';
import '../../data/profiles/series_api.dart';
import '../theme.dart';

class _Media {
  final String name;
  final String url;
  final bool live;
  final String? sid;
  const _Media(this.name, this.url, this.live, {this.sid});
}

class SectionScreen extends StatefulWidget {
  final Profile profile;
  final Catalog catalog;
  final int initialTab;
  const SectionScreen({
    super.key,
    required this.profile,
    required this.catalog,
    this.initialTab = 0,
  });

  @override
  State<SectionScreen> createState() => _SectionScreenState();
}

class _SectionScreenState extends State<SectionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final Player _player;
  late final VideoController _video;
  late final Future<void> _cfg;
  final _search = TextEditingController();
  final List<StreamSubscription> _subs = [];
  final _posN = ValueNotifier<Duration>(Duration.zero);
  final _durN = ValueNotifier<Duration>(Duration.zero);
  final Map<int, List<String>> _catCache = {};
  final Map<int, String> _fKey = {};
  final Map<int, List<Item>> _fVal = {};

  String _query = '';
  String _category = 'Todas';
  _Media? _current;
  List<_Media> _queue = [];
  List<Item> _favs = [];
  List<EpgEntry> _epg = [];
  bool _epgLoading = false;
  List<String> _cands = [];
  int _ci = 0;
  int _qIndex = -1;
  bool _full = false;
  bool _controls = true;
  bool _buffering = false;
  bool _playing = false;
  bool _dragging = false;
  double _dragValue = 0;
  String? _error;
  String _lastErr = '';
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _hideTimer;
  Timer? _openTimer;
  Timer? _epgTimer;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _tabs = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) {
        setState(() => _category = 'Todas');
      }
    });
    FavoritesStore.changes.addListener(_loadFavs);
    _loadFavs();

    _player = Player(
      configuration: const PlayerConfiguration(bufferSize: 24 * 1024 * 1024),
    );
    _video = VideoController(_player);
    _cfg = _configurePlayer();

    _subs.add(_player.stream.position.listen((p) {
      _posN.value = p;
      if (p > Duration.zero) _openTimer?.cancel();
      final now = DateTime.now();
      if (now.difference(_lastSave) > const Duration(seconds: 10)) {
        _lastSave = now;
        _saveNow();
      }
    }));
    _subs.add(_player.stream.width.listen((w) {
      if ((w ?? 0) > 0) _openTimer?.cancel();
    }));
    _subs.add(_player.stream.duration.listen((d) => _durN.value = d));
    _subs.add(_player.stream.playing.listen((v) {
      if (mounted) setState(() => _playing = v);
    }));
    _subs.add(_player.stream.buffering.listen((v) {
      if (mounted) setState(() => _buffering = v);
    }));
    _subs.add(_player.stream.error.listen((e) {
      final msg = e.toString();
      if (!mounted || msg.isEmpty) return;
      _lastErr = msg;
      if (_posN.value > const Duration(seconds: 3)) return;
      if ((_player.state.width ?? 0) > 0) return;
      _failOver();
    }));
    _subs.add(_player.stream.completed.listen((c) {
      if (c && _queue.isNotEmpty && _qIndex < _queue.length - 1) {
        _step(1);
      }
    }));

    _epgTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      final m = _current;
      if (!mounted || m == null || !m.live || _full) return;
      final now = DateTime.now();
      if (!_epgLoading && !_epg.any((e) => e.stop.isAfter(now))) {
        _loadEpg(m);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _openTimer?.cancel();
    _epgTimer?.cancel();
    FavoritesStore.changes.removeListener(_loadFavs);
    for (final s in _subs) {
      s.cancel();
    }
    _saveNow();
    _player.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _tabs.dispose();
    _search.dispose();
    _posN.dispose();
    _durN.dispose();
    super.dispose();
  }

  Future<void> _configurePlayer() async {
    final pl = _player.platform;
    if (pl is NativePlayer) {
      Future<void> set(String k, String v) async {
        try {
          await pl.setProperty(k, v);
        } catch (_) {}
      }

      await set('user-agent', 'VLC/3.0.20 LibVLC/3.0.20');
      await set('tls-verify', 'no');
      await set('network-timeout', '20');
      await set(
        'stream-lavf-o',
        'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5',
      );
      await set('cache', 'yes');
      await set('demuxer-readahead-secs', '20');
    }
  }

  // ---------- favoritos ----------

  Future<void> _loadFavs() async {
    try {
      final l = await FavoritesStore.all(widget.profile.id);
      if (!mounted) return;
      setState(() => _favs = List<Item>.from(l));
    } catch (_) {}
  }

  // ---------- progresso ----------

  Future<void> _saveNow() async {
    final m = _current;
    if (m == null || m.live) return;
    final p = _posN.value;
    final d = _durN.value;
    if (d < const Duration(minutes: 5)) return;
    try {
      await ProgressStore.save(m.url, p, d);
    } catch (_) {}
  }

  Future<Duration?> _loadSaved(String url) async {
    try {
      final dynamic v = await ProgressStore.position(url);
      if (v is Duration) return v;
    } catch (_) {}
    return null;
  }

  // ---------- programação (EPG) ----------

  Future<void> _loadEpg(_Media m) async {
    final sid = m.sid;
    if (!m.live || sid == null || !EpgApi.canLoad(widget.profile)) {
      if (mounted) {
        setState(() {
          _epg = [];
          _epgLoading = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _epg = [];
        _epgLoading = true;
      });
    }
    final l = await EpgApi.load(widget.profile, sid);
    if (!mounted || !identical(_current, m)) return;
    setState(() {
      _epg = l;
      _epgLoading = false;
    });
  }

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _epgNote(String t) => Container(
        width: double.infinity,
        color: agBlack,
        padding: const EdgeInsets.all(14),
        child: Text(t, style: const TextStyle(color: Colors.white54)),
      );

  Widget _epgPanel() {
    final cur = _current;
    if (cur == null || !cur.live) return const SizedBox.shrink();
    if (!EpgApi.canLoad(widget.profile)) {
      return _epgNote('Programação só em listas com usuário e senha.');
    }
    if (_epgLoading) return _epgNote('Carregando programação...');
    final now = DateTime.now();
    final up = _epg.where((e) => e.stop.isAfter(now)).toList();
    if (up.isEmpty) {
      return _epgNote('Programação indisponível para este canal.');
    }
    EpgEntry? nowE;
    if (!up.first.start.isAfter(now)) nowE = up.first;
    final next = nowE == null ? up : up.skip(1).toList();

    double prog = 0;
    if (nowE != null) {
      final total = nowE.stop.difference(nowE.start).inSeconds;
      final done = now.difference(nowE.start).inSeconds;
      prog = (done / (total < 1 ? 1 : total)).clamp(0.0, 1.0).toDouble();
    }

    return Container(
      width: double.infinity,
      color: agBlack,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (nowE != null) ...[
            const Text('AGORA',
                style: TextStyle(
                    color: agGold,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(nowE.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text('${_hm(nowE.start)} – ${_hm(nowE.stop)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: prog,
              minHeight: 3,
              color: agGold,
              backgroundColor: agPanelLine,
            ),
            if (nowE.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(nowE.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
          ],
          if (next.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('A SEGUIR',
                style: TextStyle(
                    color: agGold,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            for (final e in next.take(3))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(_hm(e.start),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ),
                    Expanded(
                      child: Text(e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ---------- player ----------

  _Media _media(Item it) {
    final live = it.kind == Kind.live;
    return _Media(
      it.name,
      it.url,
      live,
      sid: live ? (EpgApi.streamIdFromUrl(it.url) ?? it.id.toString()) : null,
    );
  }

  List<String> _candidatesFor(_Media m) {
    final u = m.url;
    final out = <String>[u];
    if (!m.live) return out;
    String? stem;
    if (u.endsWith('.ts')) {
      stem = u.substring(0, u.length - 3);
      out.add('$stem.m3u8');
    } else if (u.endsWith('.m3u8')) {
      stem = u.substring(0, u.length - 5);
      out.add('$stem.ts');
    }
    if (stem != null) out.add(stem);
    return out;
  }

  String _mask(String s) {
    var r = s.replaceAllMapped(
      RegExp(r'/(live|movie|series)/[^/\s]+/[^/\s]+/'),
      (m) => '/${m[1]}/***/***/',
    );
    r = r.replaceAllMapped(
      RegExp(r'(username|password)=[^&\s]+'),
      (m) => '${m[1]}=***',
    );
    return r;
  }

  Future<void> _openUrl(String u) async {
    try {
      await _player.open(Media(u), play: true);
      _openTimer?.cancel();
      _openTimer = Timer(const Duration(seconds: 25), () {
        if (mounted &&
            _posN.value == Duration.zero &&
            (_player.state.width ?? 0) == 0) {
          _failOver();
        }
      });
    } catch (_) {
      _failOver();
    }
  }

  void _failOver() {
    _openTimer?.cancel();
    if (_ci + 1 < _cands.length) {
      _ci++;
      _openUrl(_cands[_ci]);
      return;
    }
    if (!mounted) return;
    var why = _mask(_lastErr);
    if (why.length > 110) why = why.substring(0, 110);
    setState(() {
      _buffering = false;
      _error = ((_current?.live ?? false)
              ? 'Canal indisponível no momento.'
              : 'Não foi possível tocar este item.') +
          (why.isEmpty ? '' : '\n($why)');
    });
  }

  Future<void> _play(_Media m, {List<_Media>? queue, int index = -1}) async {
    await _saveNow();
    if (!mounted) return;
    _openTimer?.cancel();
    setState(() {
      _current = m;
      _error = null;
      _lastErr = '';
      _buffering = true;
      _queue = queue ?? [];
      _qIndex = index;
    });
    _posN.value = Duration.zero;
    _durN.value = Duration.zero;
    _cands = _candidatesFor(m);
    _ci = 0;
    _loadEpg(m);
    await _cfg;
    await _openUrl(_cands[0]);
    if (!m.live) {
      final saved = await _loadSaved(m.url);
      if (saved != null && saved > const Duration(seconds: 10)) {
        try {
          if (_player.state.duration == Duration.zero) {
            await _player.stream.duration
                .firstWhere((d) => d > Duration.zero)
                .timeout(const Duration(seconds: 15));
          }
          if (identical(_current, m)) await _player.seek(saved);
        } catch (_) {}
      }
    }
    _showControls();
  }

  void _step(int d) {
    final i = _qIndex + d;
    if (i < 0 || i >= _queue.length) return;
    _play(_queue[i], queue: _queue, index: i);
  }

  void _seekBy(Duration d) {
    var t = _posN.value + d;
    if (t < Duration.zero) t = Duration.zero;
    final dur = _durN.value;
    if (dur > Duration.zero && t > dur) t = dur;
    _player.seek(t);
  }

  void _showControls() {
    if (!_full) return;
    setState(() => _controls = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _full) setState(() => _controls = false);
    });
  }

  Future<void> _enterFull() async {
    setState(() => _full = true);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _showControls();
  }

  Future<void> _exitFull() async {
    _hideTimer?.cancel();
    if (mounted) setState(() => _full = false);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!_full || e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final live = _current?.live ?? true;
    if (k == LogicalKeyboardKey.arrowRight) {
      if (!live) _seekBy(const Duration(seconds: 10));
      _showControls();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (!live) _seekBy(const Duration(seconds: -10));
      _showControls();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.arrowDown) {
      _showControls();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      _player.playOrPause();
      _showControls();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- séries ----------

  Future<void> _openSeries(Item s) async {
    _snack('Carregando episódios...');
    final flat = <_Media>[];
    final seasonOf = <int>[];
    String? why;

    if (SeriesApi.canLoad(widget.profile)) {
      try {
        final eps = await SeriesApi.load(widget.profile, s.id.toString());
        for (final e in eps) {
          flat.add(_Media('E${e.number} · ${e.title}', e.url, false));
          seasonOf.add(e.season);
        }
      } catch (e) {
        why = e.toString().replaceFirst('Exception: ', '');
      }
    }
    if (flat.isEmpty) {
      try {
        final eps = List<Item>.from(
          await IptvApi.episodes(widget.profile, s),
        );
        for (final e in eps) {
          flat.add(_Media(e.name, e.url, false));
          seasonOf.add(1);
        }
      } catch (e) {
        why ??= e.toString().replaceFirst('Exception: ', '');
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (flat.isEmpty) {
      _snack(why ?? 'Nenhum episódio encontrado.');
      return;
    }

    final seasons = seasonOf.toSet().toList()..sort();
    final h = MediaQuery.of(context).size.height * 0.75;
    final pick = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: agPanel,
      isScrollControlled: true,
      builder: (ctx) {
        var sel = seasons.first;
        return StatefulBuilder(builder: (ctx, setM) {
          final idxs = <int>[
            for (var i = 0; i < flat.length; i++)
              if (seasonOf[i] == sel) i,
          ];
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      s.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: agGold,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (seasons.length > 1)
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          for (final se in seasons)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 3, vertical: 4),
                              child: ChoiceChip(
                                label: Text(
                                  'Temporada $se',
                                  style: TextStyle(
                                    color: se == sel
                                        ? Colors.black
                                        : Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                                selected: se == sel,
                                selectedColor: agGold,
                                backgroundColor: agBlack,
                                onSelected: (_) => setM(() => sel = se),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: idxs.length,
                      itemBuilder: (_, k) {
                        final gi = idxs[k];
                        return ListTile(
                          dense: true,
                          focusColor: agGold.withOpacity(0.25),
                          title: Text(
                            flat[gi].name,
                            style: const TextStyle(color: Colors.white),
                          ),
                          onTap: () => Navigator.pop(ctx, gi),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
    if (pick != null) _play(flat[pick], queue: flat, index: pick);
  }

  void _onTapItem(Item it) {
    if (it.kind == Kind.series) {
      _openSeries(it);
      return;
    }
    if (_current?.url == it.url) {
      _enterFull();
      return;
    }
    _play(_media(it));
  }

  // ---------- listas ----------

  List<Item> _itemsForTab(int tab) {
    switch (tab) {
      case 0:
        return widget.catalog.live;
      case 1:
        return widget.catalog.movies;
      case 2:
        return widget.catalog.series;
      default:
        return _favs;
    }
  }

  List<String> _categories(int tab, List<Item> all) {
    if (tab < 3 && _catCache.containsKey(tab)) return _catCache[tab]!;
    final s = <String>{};
    for (final it in all) {
      final c = it.category.toString().trim();
      if (c.isNotEmpty && c != 'null') s.add(c);
    }
    final l = <String>['Todas', ...(s.toList()..sort())];
    if (tab < 3) _catCache[tab] = l;
    return l;
  }

  List<Item> _filtered(int tab, List<Item> all, String cat) {
    final key = '$cat|$_query|${all.length}|${identityHashCode(all)}';
    if (_fKey[tab] == key) return _fVal[tab]!;
    final r = all.where((it) {
      if (cat != 'Todas' && it.category.toString().trim() != cat) {
        return false;
      }
      return _query.isEmpty || it.name.toLowerCase().contains(_query);
    }).toList();
    _fKey[tab] = key;
    _fVal[tab] = r;
    return r;
  }

  Widget _logo(Item it) {
    final l = it.logo;
    final fallback = const Icon(Icons.play_circle_outline, color: agGold);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 44,
        height: 44,
        child: (l == null || l.isEmpty)
            ? fallback
            : Image.network(
                l,
                fit: BoxFit.cover,
                cacheWidth: 100,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => fallback,
              ),
      ),
    );
  }

  Widget _row(Item it) {
    final playing = _current?.url == it.url;
    final pid = widget.profile.id;
    return ListTile(
      dense: true,
      focusColor: agGold.withOpacity(0.25),
      leading: _logo(it),
      title: Text(
        it.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: playing ? agGold : Colors.white),
      ),
      subtitle: Text(
        it.category.toString(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
      trailing: ValueListenableBuilder(
        valueListenable: FavoritesStore.changes,
        builder: (_, __, ___) {
          final fav = FavoritesStore.has(pid, it);
          return IconButton(
            icon: Icon(
              fav ? Icons.favorite : Icons.favorite_border,
              color: agGold,
            ),
            onPressed: () => FavoritesStore.toggle(pid, it),
          );
        },
      ),
      onTap: () => _onTapItem(it),
    );
  }

  Widget _pageBody(int tab) {
    final all = _itemsForTab(tab);
    final cats = _categories(tab, all);
    final cat = cats.contains(_category) ? _category : 'Todas';
    final list = _filtered(tab, all, cat);

    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: cats.length,
            itemBuilder: (_, i) {
              final c = cats[i];
              final sel = c == cat;
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                child: ChoiceChip(
                  label: Text(
                    c,
                    style: TextStyle(
                      color: sel ? Colors.black : Colors.white,
                      fontSize: 12,
                    ),
                  ),
                  selected: sel,
                  selectedColor: agGold,
                  backgroundColor: agPanel,
                  onSelected: (_) => setState(() => _category = c),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    tab == 3
                        ? 'Nenhum favorito ainda. Toque no coração.'
                        : 'Nada encontrado.',
                    style: const TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.builder(
                  itemCount: list.length,
                  itemExtent: 64,
                  itemBuilder: (_, i) => _row(list[i]),
                ),
        ),
      ],
    );
  }

  // ---------- controles ----------

  Widget _controlsPanel() {
    final cur = _current;
    final live = cur?.live ?? false;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (cur != null && !live)
          ValueListenableBuilder<Duration>(
            valueListenable: _posN,
            builder: (_, pos, __) {
              return ValueListenableBuilder<Duration>(
                valueListenable: _durN,
                builder: (_, dur, __) {
                  final maxMs = dur.inMilliseconds.toDouble();
                  final top = maxMs > 0 ? maxMs : 1.0;
                  final raw =
                      _dragging ? _dragValue : pos.inMilliseconds.toDouble();
                  final v = raw.clamp(0.0, top).toDouble();
                  final shown = Duration(milliseconds: v.toInt());
                  return Row(
                    children: [
                      const SizedBox(width: 10),
                      Text(
                        _fmt(shown),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                      Expanded(
                        child: Slider(
                          value: v,
                          min: 0,
                          max: top,
                          activeColor: agGold,
                          inactiveColor: agPanelLine,
                          onChangeStart: (_) =>
                              setState(() => _dragging = true),
                          onChanged: (x) => setState(() => _dragValue = x),
                          onChangeEnd: (x) {
                            _player.seek(Duration(milliseconds: x.toInt()));
                            setState(() => _dragging = false);
                          },
                        ),
                      ),
                      Text(
                        _fmt(dur),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(width: 10),
                    ],
                  );
                },
              );
            },
          ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_queue.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.skip_previous, color: agGold),
                onPressed: () => _step(-1),
              ),
            if (cur != null && !live)
              TextButton(
                onPressed: () => _seekBy(const Duration(minutes: -5)),
                child: const Text('-5m', style: TextStyle(color: agGold)),
              ),
            if (cur != null && !live)
              IconButton(
                icon: const Icon(Icons.replay_10, color: agGold),
                onPressed: () => _seekBy(const Duration(seconds: -10)),
              ),
            IconButton(
              iconSize: 36,
              icon: Icon(
                _playing ? Icons.pause_circle : Icons.play_circle,
                color: agGold,
              ),
              onPressed: () => _player.playOrPause(),
            ),
            if (cur != null && !live)
              IconButton(
                icon: const Icon(Icons.forward_10, color: agGold),
                onPressed: () => _seekBy(const Duration(seconds: 10)),
              ),
            if (cur != null && !live)
              TextButton(
                onPressed: () => _seekBy(const Duration(minutes: 5)),
                child: const Text('+5m', style: TextStyle(color: agGold)),
              ),
            if (_queue.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.skip_next, color: agGold),
                onPressed: () => _step(1),
              ),
            IconButton(
              icon: Icon(
                _full ? Icons.fullscreen_exit : Icons.fullscreen,
                color: agGold,
              ),
              onPressed: () => _full ? _exitFull() : _enterFull(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _videoBox() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_full) {
          if (_controls) {
            setState(() => _controls = false);
          } else {
            _showControls();
          }
        } else {
          _player.playOrPause();
        }
      },
      onDoubleTap: () => _full ? _exitFull() : _enterFull(),
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(controller: _video, controls: NoVideoControls),
            if (_current == null)
              const Center(
                child: Text(
                  'Escolha algo para assistir',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            if (_buffering && _error == null && _current != null)
              const Center(child: CircularProgressIndicator(color: agGold)),
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ),
            if (_full && _controls)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black54,
                  child: SafeArea(top: false, child: _controlsPanel()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _playerArea({required bool wide}) {
    final cur = _current;
    final h = MediaQuery.of(context).size.height;
    final video = wide
        ? Container(
            color: Colors.black,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: h * 0.5),
                child: AspectRatio(aspectRatio: 16 / 9, child: _videoBox()),
              ),
            ),
          )
        : AspectRatio(aspectRatio: 16 / 9, child: _videoBox());
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        video,
        if (cur != null)
          Container(
            width: double.infinity,
            color: agPanel,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              cur.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        Container(
          width: double.infinity,
          color: agPanel,
          child: _controlsPanel(),
        ),
        if (wide) _epgPanel(),
      ],
    );
  }

  Widget _searchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: TextField(
        controller: _search,
        style: const TextStyle(color: Colors.white),
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: agPanel,
          hintText: 'Buscar',
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, color: agGold),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _listArea({required bool tabs}) {
    return Column(
      children: [
        if (tabs)
          TabBar(
            controller: _tabs,
            labelColor: agGold,
            unselectedLabelColor: Colors.white70,
            indicatorColor: agGold,
            tabs: const [
              Tab(text: 'Ao vivo'),
              Tab(text: 'Filmes'),
              Tab(text: 'Séries'),
              Tab(text: 'Favoritos'),
            ],
          ),
        _searchBox(),
        Expanded(
          child: tabs
              ? TabBarView(
                  controller: _tabs,
                  children: [for (var i = 0; i < 4; i++) _pageBody(i)],
                )
              : _pageBody(_tabs.index),
        ),
      ],
    );
  }

  Widget _navBtn(IconData icon, String label, int i) {
    final sel = _tabs.index == i;
    final color = sel ? agGold : Colors.white70;
    return InkWell(
      focusColor: agGold.withOpacity(0.25),
      onTap: () {
        _tabs.index = i;
        setState(() => _category = 'Todas');
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        color: sel ? agGold.withOpacity(0.15) : Colors.transparent,
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _sideMenu() {
    return Container(
      width: 84,
      color: agPanel,
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 4),
            IconButton(
              icon: const Icon(Icons.arrow_back, color: agGold),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: 4),
            _navBtn(Icons.live_tv, 'Ao vivo', 0),
            _navBtn(Icons.movie, 'Filmes', 1),
            _navBtn(Icons.video_library, 'Séries', 2),
            _navBtn(Icons.favorite, 'Favoritos', 3),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_full) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _exitFull();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Focus(
            autofocus: true,
            onKeyEvent: _onKey,
            child: _videoBox(),
          ),
        ),
      );
    }

    final wide = MediaQuery.of(context).size.width >= 640;

    if (wide) {
      return Scaffold(
        backgroundColor: agBlack,
        body: SafeArea(
          child: Row(
            children: [
              _sideMenu(),
              Expanded(flex: 4, child: _listArea(tabs: false)),
              Expanded(
                flex: 6,
                child: SingleChildScrollView(
                  child: _playerArea(wide: true),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: agBlack,
      appBar: AppBar(
        backgroundColor: agBlack,
        foregroundColor: agGold,
        toolbarHeight: 44,
        title: Text(
          widget.profile.name,
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: Column(
        children: [
          _playerArea(wide: false),
          Expanded(child: _listArea(tabs: true)),
        ],
      ),
    );
  }
}
