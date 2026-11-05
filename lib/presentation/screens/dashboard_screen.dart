import 'package:flutter/material.dart';

import '../../data/profiles/info_api.dart';
import '../../data/profiles/iptv_api.dart';
import '../../data/profiles/profile.dart';
import '../theme.dart';
import 'section_screen.dart';

class DashboardScreen extends StatefulWidget {
  final Profile profile;
  final Catalog catalog;
  const DashboardScreen({
    super.key,
    required this.profile,
    required this.catalog,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Item? _sel;
  ItemInfo? _info;
  int _selTab = 1;

  List<Item> _recent(List<Item> l) => l.reversed.take(10).toList();

  @override
  void initState() {
    super.initState();
    final m = _recent(widget.catalog.movies);
    final s = _recent(widget.catalog.series);
    if (m.isNotEmpty) {
      _select(m.first, 1);
    } else if (s.isNotEmpty) {
      _select(s.first, 2);
    }
  }

  void _select(Item it, int tab) {
    setState(() {
      _sel = it;
      _selTab = tab;
      _info = null;
    });
    InfoApi.load(widget.profile, it).then((i) {
      if (mounted && _sel == it) setState(() => _info = i);
    }).catchError((_) {});
  }

  void _go(int tab) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SectionScreen(
          profile: widget.profile,
          catalog: widget.catalog,
          initialTab: tab,
        ),
      ),
    );
  }

  Widget _poster(Item it, double w, double h) {
    final l = it.logo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: w,
        height: h,
        color: agPanel,
        child: (l == null || l.isEmpty)
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    it.name,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              )
            : Image.network(
                l,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    it.name,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _shelf(String title, List<Item> items, int tab) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Text(title,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final it = items[i];
              final selected = _sel == it;
              return GestureDetector(
                onTap: () => _select(it, tab),
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 80,
                          fontWeight: FontWeight.bold,
                          height: 1,
                          color: agGold.withOpacity(0.35),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected ? agGold : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: _poster(it, 100, 150),
                      ),
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

  Widget _highlight() {
    final it = _sel;
    if (it == null) return const SizedBox.shrink();
    final i = _info;
    String t(dynamic v) {
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? 'N/A' : s;
    }

    Widget line(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: '$k: ',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            TextSpan(text: v, style: const TextStyle(color: Colors.white70)),
          ])),
        );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (i != null) ...[
                  line('Direção', t(i.director)),
                  line('Duração', t(i.duration)),
                  line('Gênero', t(i.genre)),
                  line('Elenco', t(i.cast)),
                  const SizedBox(height: 4),
                  Text(t(i.plot),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13)),
                ] else
                  Text(
                    'Categoria: ${it.category}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                const SizedBox(height: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: agGold,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () => _go(_selTab),
                  child: const Text('Abrir'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _poster(it, 110, 160),
        ],
      ),
    );
  }

  Widget _content() {
    return ListView(
      children: [
        _highlight(),
        _shelf('Top Filmes Recém Adicionados',
            _recent(widget.catalog.movies), 1),
        _shelf('Top Séries Recém Adicionadas',
            _recent(widget.catalog.series), 2),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final menu = <(IconData, String, VoidCallback)>[
      (Icons.home, 'Início', () {}),
      (Icons.live_tv, 'Canais', () => _go(0)),
      (Icons.movie, 'Filmes', () => _go(1)),
      (Icons.video_library, 'Séries', () => _go(2)),
      (Icons.favorite, 'Favoritos', () => _go(3)),
      (Icons.person, 'Perfis', () => Navigator.of(context).pop()),
    ];

    return Scaffold(
      backgroundColor: agBlack,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 700;
          if (wide) {
            return Row(
              children: [
                Container(
                  width: 130,
                  color: agPanel,
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('AG PLAYER',
                            style: TextStyle(
                                color: agGold,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2)),
                      ),
                      for (final m in menu)
                        ListTile(
                          dense: true,
                          leading: Icon(m.$1, color: agGold, size: 20),
                          title: Text(m.$2,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                          onTap: m.$3,
                        ),
                    ],
                  ),
                ),
                Expanded(child: _content()),
              ],
            );
          }
          return Column(
            children: [
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final m in menu)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 8),
                        child: ActionChip(
                          backgroundColor: agPanel,
                          side: const BorderSide(color: agPanelLine),
                          avatar: Icon(m.$1, color: agGold, size: 16),
                          label: Text(m.$2,
                              style: const TextStyle(color: Colors.white)),
                          onPressed: m.$3,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(child: _content()),
            ],
          );
        }),
      ),
    );
  }
}
