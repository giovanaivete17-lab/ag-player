
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/profiles/profile.dart';
import '../../data/profiles/iptv_api.dart';
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
    final l = await ProfileStore.load();
    final a = await ProfileStore.activeId();

    if (!mounted) return;

    setState(() {
      _list = l;
      _activeId = a;
      _loading = false;
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _add() async {
    final p = await showDialog<Profile>(
      context: context,
      builder: (_) => const _AddDialog(),
    );

    if (p == null) return;

    try {
      final next = [..._list, p];
      await ProfileStore.save(next);

      if (!mounted) return;

      setState(() => _list = next);
      _snack('Conexão salva com sucesso!');
    } catch (e) {
      _snack('Erro ao salvar conexão: $e');
    }
  }

  Future<void> _remove(Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover conexão?'),
        content: Text(p.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final next = _list.where((e) => e.id != p.id).toList();
    await ProfileStore.save(next);

    if (!mounted) return;

    setState(() => _list = next);
  }

  Future<void> _select(Profile p) async {
    await ProfileStore.setActive(p.id);

    if (!mounted) return;

    Navigator.of(context).pop(p);
  }

  String _description(Profile p) {
    if (p.type == 'xtream') return 'Xtream Codes';
    if (p.type == 'm3u_file') return 'Arquivo M3U';
    return 'Lista M3U por URL';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: agBlack,
      appBar: AppBar(
        backgroundColor: agBlack,
        foregroundColor: agGold,
        title: const Text('Minhas conexões'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: agGold,
        foregroundColor: Colors.black,
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Adicionar conexão'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: agGold),
            )
          : _list.isEmpty
              ? const Center(
                  child: Text(
                    'Bem-vindo ao AG PLAYER!\n\nAdicione sua primeira conexão.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                  itemCount: _list.length,
                  itemBuilder: (_, i) {
                    final p = _list[i];

                    return Card(
                      color: agPanel,
                      child: ListTile(
                        leading: Icon(
                          p.type == 'xtream'
                              ? Icons.dns
                              : p.type == 'm3u_file'
                                  ? Icons.folder
                                  : Icons.link,
                          color: agGold,
                        ),
                        title: Text(
                          p.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          _description(p),
                          style: const TextStyle(color: Colors.white54),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.white54,
                          ),
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

  int _mode = 0;
  String? _filePath;
  String? _fileName;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m3u', 'm3u8'],
      withData: true,
    );

    if (result == null) return;

    final bytes = result.files.single.bytes;

    if (bytes == null || bytes.isEmpty) {
      setState(() => _error = 'Não foi possível ler o arquivo.');
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/AGPlayer/listas');

    await folder.create(recursive: true);

    final file = File(
      '${folder.path}/${DateTime.now().microsecondsSinceEpoch}_${result.files.single.name}',
    );

    await file.writeAsBytes(bytes, flush: true);

    if (!mounted) return;

    setState(() {
      _filePath = file.path;
      _fileName = result.files.single.name;
      _error = null;
    });
  }

  void _ok() {
    if (_mode == 0 &&
        (_user.text.trim().isEmpty || _pass.text.trim().isEmpty)) {
      setState(() => _error = 'Informe usuário e senha.');
      return;
    }

    if (_mode == 1 && _url.text.trim().isEmpty) {
      setState(() => _error = 'Informe a URL M3U.');
      return;
    }

    if (_mode == 2 && _filePath == null) {
      setState(() => _error = 'Selecione um arquivo M3U.');
      return;
    }

    final type = ['xtream', 'm3u', 'm3u_file'][_mode];

    Navigator.pop(
      context,
      Profile(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: _name.text.trim().isEmpty
            ? 'Minha conexão'
            : _name.text.trim(),
        type: type,
        url: _mode == 0
            ? IptvApi.defaultServer
            : _mode == 1
                ? _url.text.trim()
                : _filePath!,
        user: _mode == 0 ? _user.text.trim() : '',
        pass: _mode == 0 ? _pass.text.trim() : '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: agPanel,
      title: const Text(
        'Nova conexão',
        style: TextStyle(color: agGold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _option('Xtream', 0),
                _option('URL M3U', 1),
                _option('Arquivo', 2),
              ],
            ),
            TextField(
              controller: _name,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Nome da conexão',
              ),
            ),
            if (_mode == 0) ...[
              TextField(
                controller: _user,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Usuário'),
              ),
              TextField(
                controller: _pass,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Senha'),
              ),
            ],
            if (_mode == 1)
              TextField(
                controller: _url,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'URL M3U'),
              ),
            if (_mode == 2)
              Column(
                children: [
                  ElevatedButton(
                    onPressed: _pickFile,
                    child: const Text('Escolher arquivo M3U'),
                  ),
                  if (_fileName != null)
                    Text(
                      _fileName!,
                      style: const TextStyle(color: Colors.white),
                    ),
                ],
              ),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _ok,
          child: const Text('Salvar'),
        ),
      ],
    );
  }

  Widget _option(String title, int value) {
    return Expanded(
      child: TextButton(
        onPressed: () => setState(() {
          _mode = value;
          _error = null;
        }),
        child: Text(
          title,
          style: TextStyle(
            color: _mode == value ? agGold : Colors.white70,
          ),
        ),
      ),
    );
  }
}
