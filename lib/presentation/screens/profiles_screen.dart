import 'package:flutter/material.dart';

import '../../data/profiles/profile.dart';
import '../theme.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  List<Profile> _list = [];
  String? _activeId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await ProfileStore.load();
      final a = await ProfileStore.activeId();
      if (!mounted) return;
      setState(() {
        _list = l;
        _activeId = a;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _add() async {
    final p = await showDialog<Profile>(
      context: context,
      builder: (_) => const _AddDialog(),
    );
    if (p == null) return;
    final next = [..._list, p];
    try {
      await ProfileStore.save(next);
      if (!mounted) return;
      setState(() => _list = next);
      _snack('Lista salva. Toque nela para entrar.');
    } catch (e) {
      _snack('Não consegui salvar: $e');
    }
  }

  Future<void> _remove(Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: agPanel,
        title: const Text('Remover lista?',
            style: TextStyle(color: Colors.white)),
        content: Text(p.name, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: agGold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final next = _list.where((e) => e.id != p.id).toList();
    try {
      await ProfileStore.save(next);
      if (!mounted) return;
      setState(() => _list = next);
    } catch (e) {
      _snack('Não consegui remover: $e');
    }
  }

  Future<void> _select(Profile p) async {
    await ProfileStore.setActive(p.id);
    if (!mounted) return;
    Navigator.of(context).pop(p);
  }

  String _host(String u) {
    final uri = Uri.tryParse(u);
    if (uri != null && uri.host.isNotEmpty) return uri.host;
    return u;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: agBlack,
      appBar: AppBar(
        backgroundColor: agBlack,
        foregroundColor: agGold,
        title: const Text('Minhas listas'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: agGold,
        foregroundColor: Colors.black,
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Adicionar lista'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: agGold))
          : _list.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nenhuma lista salva ainda.\nToque em "Adicionar lista".',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                  itemCount: _list.length,
                  itemBuilder: (_, i) {
                    final p = _list[i];
                    final active = p.id == _activeId;
                    return Card(
                      color: agPanel,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: active ? agGold : agPanelLine,
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          p.type == 'xtream' ? Icons.dns : Icons.list_alt,
                          color: agGold,
                        ),
                        title: Text(p.name,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          '${p.type == 'xtream' ? 'Xtream' : 'M3U'} · ${_host(p.url)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.white54),
                          onPressed: () => _remove(p),
                        ),
                        onTap: () => _select(p),
                      ),
                    );
                  },
                ),
    );
  }
}

class _AddDialog extends StatefulWidget {
  const _AddDialog();

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _xtream = true;
  String? _err;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: agPanelLine),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: agGold),
        ),
      );

  void _ok() {
    var url = _url.text.trim();
    final name = _name.text.trim();
    if (url.isEmpty) {
      setState(() => _err = _xtream ? 'Preencha o servidor.' : 'Cole o link da lista.');
      return;
    }
    if (_xtream) {
      if (_user.text.trim().isEmpty || _pass.text.trim().isEmpty) {
        setState(() => _err = 'Preencha usuário e senha.');
        return;
      }
      if (!url.startsWith('http')) url = 'http://$url';
      while (url.endsWith('/')) {
        url = url.substring(0, url.length - 1);
      }
    }
    final p = Profile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.isEmpty ? 'Minha lista' : name,
      type: _xtream ? 'xtream' : 'm3u',
      url: url,
      user: _xtream ? _user.text.trim() : '',
      pass: _xtream ? _pass.text.trim() : '',
    );
    Navigator.of(context).pop(p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: agPanel,
      title: const Text('Adicionar lista',
          style: TextStyle(color: agGold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Usuário e senha'),
                  selected: _xtream,
                  selectedColor: agGold,
                  backgroundColor: agBlack,
                  labelStyle: TextStyle(
                      color: _xtream ? Colors.black : Colors.white,
                      fontSize: 12),
                  onSelected: (_) => setState(() => _xtream = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Link M3U'),
                  selected: !_xtream,
                  selectedColor: agGold,
                  backgroundColor: agBlack,
                  labelStyle: TextStyle(
                      color: !_xtream ? Colors.black : Colors.white,
                      fontSize: 12),
                  onSelected: (_) => setState(() => _xtream = false),
                ),
              ],
            ),
            TextField(
              controller: _name,
              style: const TextStyle(color: Colors.white),
              decoration: _dec('Nome (opcional)'),
            ),
            TextField(
              controller: _url,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration:
                  _dec(_xtream ? 'Servidor (ex: http://site.com:8080)' : 'Link da lista M3U'),
            ),
            if (_xtream) ...[
              TextField(
                controller: _user,
                style: const TextStyle(color: Colors.white),
                autocorrect: false,
                decoration: _dec('Usuário'),
              ),
              TextField(
                controller: _pass,
                style: const TextStyle(color: Colors.white),
                autocorrect: false,
                obscureText: true,
                decoration: _dec('Senha'),
              ),
            ],
            if (_err != null) ...[
              const SizedBox(height: 10),
              Text(_err!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: _ok,
          child: const Text('Salvar', style: TextStyle(color: agGold)),
        ),
      ],
    );
  }
}
