import 'package:flutter/material.dart';
import '../../data/profiles/profile.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  List<Profile> _profiles = <Profile>[];
  String? _active;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ProfileStore.load();
    final a = await ProfileStore.activeId();
    if (!mounted) return;
    setState(() {
      _profiles = list;
      _active = a;
      _loading = false;
    });
  }

  Future<void> _select(Profile p) async {
    await ProfileStore.setActive(p.id);
    if (!mounted) return;
    Navigator.of(context).pop(p);
  }

  Future<void> _add() async {
    final p = await showDialog<Profile>(
      context: context,
      builder: (_) => const _AddDialog(),
    );
    if (p == null) return;
    final list = <Profile>[..._profiles, p];
    await ProfileStore.save(list);
    await _select(p);
  }

  Future<void> _delete(Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover lista?'),
        content: Text('A lista "${p.name}" será removida do app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final list = _profiles.where((e) => e.id != p.id).toList();
    await ProfileStore.save(list);
    if (_active == p.id) await ProfileStore.setActive(null);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Listas de reprodução')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_profiles.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'Nenhuma lista ainda.\nToque em "Adicionar lista" para começar.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final p in _profiles)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(p.type == 'xtream'
                            ? Icons.dns_rounded
                            : Icons.music_note_rounded),
                      ),
                      title: Text(p.name),
                      subtitle: Text(p.type == 'xtream' ? 'Xtream' : 'M3U'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_active == p.id)
                            Icon(Icons.check_circle, color: cs.primary),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(p),
                          ),
                        ],
                      ),
                      onTap: () => _select(p),
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Adicionar lista'),
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
  String _type = 'xtream';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _save() {
    final url = _url.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Digite o endereço.');
      return;
    }
    if (_type == 'xtream' &&
        (_user.text.trim().isEmpty || _pass.text.trim().isEmpty)) {
      setState(() => _error = 'Digite usuário e senha.');
      return;
    }
    final name = _name.text.trim().isEmpty ? 'Minha lista' : _name.text.trim();
    Navigator.of(context).pop(Profile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      type: _type,
      url: url,
      user: _user.text.trim(),
      pass: _pass.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adicionar lista'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'xtream', label: Text('Xtream')),
                ButtonSegment(value: 'm3u', label: Text('Link M3U')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nome da lista'),
            ),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: _type == 'xtream'
                    ? 'Endereço (ex: http://servidor.com:8080)'
                    : 'Link da lista M3U',
              ),
            ),
            if (_type == 'xtream') ...[
              TextField(
                controller: _user,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Usuário'),
              ),
              TextField(
                controller: _pass,
                autocorrect: false,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Senha'),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}
