import 'package:flutter/material.dart';

import '../../data/profiles/favorites_store.dart';
import '../../data/profiles/iptv_api.dart';
import '../../data/profiles/profile.dart';
import 'dashboard_screen.dart';
import 'profiles_screen.dart';

const _white = Colors.white;
const _black = Color(0xFF000000);
const _red = Color(0xFFE53935);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Profile? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final profiles = await ProfileStore.load();
      final id = await ProfileStore.activeId();
      Profile? found;
      for (final p in profiles) {
        if (p.id == id) found = p;
      }
      if (!mounted) return;
      if (found == null) {
        setState(() => _loading = false);
        await _choose();
      } else {
        _profile = found;
        await _open(found);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _choose() async {
    final p = await Navigator.of(context).push<Profile>(
      MaterialPageRoute(builder: (_) => const ProfilesScreen()),
    );
    if (p == null || !mounted) return;
    await ProfileStore.setActive(p.id);
    _profile = p;
    await _open(p);
  }

  Future<void> _open(Profile p) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await IptvApi.load(p);
      await FavoritesStore.preload(p.id);
      if (!mounted) return;
      setState(() => _loading = false);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DashboardScreen(
            profile: p,
            catalog: catalog,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _white,
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'AG PLAYER',
                      style: TextStyle(
                        color: _black,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(width: 80, height: 4, color: _red),
                    const SizedBox(height: 32),
                    if (_loading) ...[
                      const CircularProgressIndicator(color: _red),
                      const SizedBox(height: 16),
                      const Text(
                        'Carregando sua lista...',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ] else ...[
                      if (_error != null) ...[
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _red),
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (_profile != null)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _red,
                              foregroundColor: _white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () => _open(_profile!),
                            child: Text('Entrar em ${_profile!.name}'),
                          ),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _black,
                            side: const BorderSide(color: _red, width: 2),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _choose,
                          child: const Text('Perfis / adicionar lista'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(height: 6, color: _red),
          ),
        ],
      ),
    );
  }
}
