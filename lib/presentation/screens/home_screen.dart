import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../data/profiles/iptv_api.dart';
import '../../data/profiles/profile.dart';
import 'profiles_screen.dart';

const _headers = {'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18'};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final TextEditingController _search = TextEditingController();

  Profile? _profile;
  Catalog? _catalog;
  bool _loading = true;
  String? _error;
  bool _full = false;
  Item? _current;

  final Map<Kind, String?> _cat = {
    Kind.live: null,
    Kind.movie: null,
    Kind.series: null,
  };
  final Map<Kind, List<String>> _cats = {
    Kind.live: <String>[],
    Kind.movie: <String>[],
    Kind.series: <String>[],
  };

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _player.dispose();
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final list = await ProfileStore.load();
    final id = await ProfileStore.activeId();
    Profile? active;
    for (final p in list) {
      if (p.id == id) active = p;
    }
    if (active == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _openProfiles());
      return;
    }
    await _loadProfile(active);
  }

  String _friendly(Object e) {
    final t = e.toString();
    final short = t.length > 140 ? '${t.substring(0, 140)}...' : t;
    if (t.contains('DioException')) {
      return 'Não foi possível baixar a lista. Confira endereço, usuário e senha.\n\n$short';
    }
    return short;
  }

  List<String> _catsOf(List<Item> items) {
    final s = <String>{};
    for (final i in items) {
      s.add(i.category);
    }
    final l = s.toList();
    l.sort();
    return l;
  }

  Future<void> _loadProfile(Profile p) async {
    setState(() {
      _profile = p;
      _loading = true;
      _error = null;
      _catalog = null;
      _cat[Kind.live] = null;
      _cat[Kind.movie] = null;
      _cat[Kind.series] = null;
    });
    try {
      final c = await IptvApi.load(p);
      if (!mounted) return;
      _cats[Kind.live] = _catsOf(c.live);
      _cats[Kind.movie] = _catsOf(c.movies);
      _cats[Kind.series] = _catsOf(c.series);
      setState(() {
        _catalog = c;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendly(e);
        _loading = false;
      });
    }
  }

  Future<void> _openProfiles() async {
    if (!mounted) return;
    final p = await Navigator.of(context).push<Profile>(
      MaterialPageRoute(builder: (_) => const ProfilesScreen()),
    );
    if (p != null) {
      await _player.stop();
      if (!mounted) return;
      setState(() => _current = null);
      await _loadProfile(p);
    }
  }

  Future<void> _play(Item it) async {
    setState(() => _current = it);
    await _player.open(Media(it.url, httpHeaders: _headers));
  }

  Future<void> _select(Item it, {bool full = false}) async {
    if (it.url.isEmpty) {
      _openSeries(it);
      return;
    }
    await _play(it);
    if (full) await _enterFull();
  }

  Future<void> _enterFull() async {
    if (_full || !mounted) return;
    setState(() => _full = true);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreen(controller: _controller, player: _player),
      ),
    );
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) setState(() => _full = false);
  }

  void _openSeries(Item serie) {
    final p = _profile;
    if (p == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  serie.name,
                  style: Theme.of(ctx).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Item>>(
                  future: IptvApi.episodes(p, serie),
                  builder: (c, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return const Center(
                        child: Text('Não foi possível carregar os episódios.'),
                      );
                    }
                    final eps = snap.data ?? <Item>[];
                    if (eps.isEmpty) {
                      return const Center(child: Text('Sem episódios.'));
                    }
                    return ListView.builder(
                      itemCount: eps.length,
                      itemBuilder: (c2, i) {
                        final ep = eps[i];
                        return ListTile(
                          leading: const Icon(Icons.play_circle_outline),
                          title: Text(ep.name),
                          onTap: () async {
                            Navigator.of(ctx).pop();
                            await _play(ep);
                            await _enterFull();
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Item> _itemsOf(Kind k) {
    final c = _catalog;
    if (c == null) return <Item>[];
    return switch (k) {
      Kind.live => c.live,
      Kind.movie => c.movies,
      Kind.series => c.series,
    };
  }

  Widget _thumb(Item it) {
    final fallback = Container(
      width: 48,
      height: 48,
      color: Colors.white10,
      child: Icon(it.kind == Kind.live ? Icons.live_tv : Icons.movie, size: 22),
    );
    final logo = it.logo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: logo == null
          ? fallback
          : Image.network(
              logo,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              cacheWidth: 120,
              errorBuilder: (_, __, ___) => fallback,
            ),
    );
  }

  Widget _tabBody(Kind k) {
    final all = _itemsOf(k);
    final cats = _cats[k] ?? <String>[];
    final sel = _cat[k];
    final q = _search.text.trim().toLowerCase();
    final shown = all.where((i) {
      final okCat = sel == null || i.category == sel;
      final okQ = q.isEmpty || i.name.toLowerCase().contains(q);
      return okCat && okQ;
    }).toList();

    return Column(
      children: [
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('Todos'),
                  selected: sel == null,
                  onSelected: (_) => setState(() => _cat[k] = null),
                ),
              ),
              for (final c in cats)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c),
                    selected: sel == c,
                    onSelected: (_) => setState(() => _cat[k] = c),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Text('Nada encontrado.'))
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final it = shown[index];
                    final playing =
                        _current != null && _current!.id == it.id && _current!.kind == it.kind;
                    return InkWell(
                      onTap: () => _select(it),
                      onDoubleTap: () => _select(it, full: true),
                      child: Container(
                        color: playing ? Colors.white10 : null,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            _thumb(it),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                it.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (playing)
                              const Icon(Icons.equalizer, size: 20),
                            if (it.url.isEmpty)
                              const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _videoArea() {
    final cur = _current;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: (cur == null || _full)
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.live_tv, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      cur == null ? 'SELECIONE UM CANAL' : cur.name,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : GestureDetector(
                onDoubleTap: _enterFull,
                child: Video(
                  controller: _controller,
                  controls: NoVideoControls,
                ),
              ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  final p = _profile;
                  if (p != null) _loadProfile(p);
                },
                child: const Text('Tentar de novo'),
              ),
              TextButton(
                onPressed: _openProfiles,
                child: const Text('Trocar lista'),
              ),
            ],
          ),
        ),
      );
    }
    final c = _catalog;
    if (c == null) {
      return Center(
        child: FilledButton.icon(
          onPressed: _openProfiles,
          icon: const Icon(Icons.playlist_add),
          label: const Text('Escolher ou adicionar lista'),
        ),
      );
    }
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: 'Ao vivo (${c.live.length})'),
            Tab(text: 'Filmes (${c.movies.length})'),
            Tab(text: 'Séries (${c.series.length})'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _tabBody(Kind.live),
              _tabBody(Kind.movie),
              _tabBody(Kind.series),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_profile?.name ?? 'AG PLAYER'),
        actions: [
          IconButton(
            tooltip: 'Listas',
            icon: const Icon(Icons.playlist_play),
            onPressed: _openProfiles,
          ),
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final p = _profile;
              if (p != null) _loadProfile(p);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _videoArea(),
          Expanded(child: _body()),
        ],
      ),
    );
  }
}

class _FullScreen extends StatefulWidget {
  final VideoController controller;
  final Player player;

  const _FullScreen({required this.controller, required this.player});

  @override
  State<_FullScreen> createState() => _FullScreenState();
}

class _FullScreenState extends State<_FullScreen> {
  bool _fill = true;
  bool _bar = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _bar = !_bar),
              onDoubleTap: () => Navigator.of(context).pop(),
              child: Video(
                controller: widget.controller,
                controls: NoVideoControls,
                fit: _fill ? BoxFit.cover : BoxFit.contain,
              ),
            ),
          ),
          if (_bar)
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _fill = !_fill),
                    child: Text(_fill ? 'Preencher' : 'Original'),
                  ),
                  IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => widget.player.playOrPause(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
