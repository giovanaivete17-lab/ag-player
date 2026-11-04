import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../data/parsers/m3u_parser.dart';
import '../../data/xtream/xtream_client.dart';
import '../../domain/entities/channel.dart';
import '../../services/player_service.dart';
import '../../services/download_service.dart';

final playerProvider = Provider<PlayerService>((ref) {
  final service = PlayerService();
  ref.onDispose(service.dispose);
  return service;
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _url = TextEditingController();
  final _host = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _search = TextEditingController();
  final _urlFocus = FocusNode();
  final _importFocus = FocusNode();
  final _loginFocus = FocusNode();

  List<Channel> _channels = [];
  List<Channel> _visible = [];
  Channel? _selected;
  bool _loading = false;
  bool _downloading = false;
  double _downloadProgress = 0;
  String _downloadStatus = '';
  final _downloadUrl = TextEditingController();
  final _downloadName = TextEditingController();
  final _downloadService = EpisodeDownloadService();
  String _status = 'Adicione uma lista M3U ou entre com Xtream Codes.';
  String _category = 'Todos';
  String _aspect = 'Original';

  PlayerService get _player => ref.read(playerProvider);
  late final VideoController _videoController;

  @override
  void initState() {
    super.initState();
    _videoController = VideoController(_player.player);
  }

  @override
  void dispose() {
    _url.dispose();
    _host.dispose();
    _username.dispose();
    _password.dispose();
    _search.dispose();
    _downloadUrl.dispose();
    _downloadName.dispose();
    _urlFocus.dispose();
    _importFocus.dispose();
    _loginFocus.dispose();
    super.dispose();
  }

  Future<void> _loadM3u(String content) async {
    setState(() {
      _loading = true;
      _status = 'Processando lista em segundo plano...';
    });
    try {
      final parsed = await M3uParser.parse(content);
      if (!mounted) return;
      setState(() {
        _channels = parsed;
        _visible = parsed;
        _selected = null;
        _loading = false;
        _status = '${parsed.length} canais carregados.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Falha ao processar lista: $e';
      });
    }
  }

  Future<void> _loadUrl() async {
    final value = _url.text.trim();
    if (value.isEmpty) return;
    setState(() => _loading = true);
    try {
      final response = await Dio().get<String>(
        value,
        options: Options(responseType: ResponseType.plain),
      );
      await _loadM3u(response.data ?? '');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Não foi possível baixar a lista: $e';
      });
    }
  }

  Future<void> _loadFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m3u', 'm3u8', 'txt'],
      withData: true,
    );
    if (result == null) return;
    final file = result.files.single;
    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) return;
    await _loadM3u(String.fromCharCodes(bytes));
  }

  Future<void> _loginXtream() async {
    if (_host.text.trim().isEmpty ||
        _username.text.trim().isEmpty ||
        _password.text.isEmpty) {
      setState(() => _status = 'Preencha URL, usuário e senha.');
      return;
    }
    setState(() {
      _loading = true;
      _status = 'Validando acesso Xtream...';
    });
    try {
      final client = XtreamClient(
        host: _host.text,
        username: _username.text,
        password: _password.text,
      );
      await client.authenticate();
      final data = await client.liveStreams();
      final parsed = data.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        final id = map['stream_id'];
        final extension = (map['container_extension'] ?? 'ts').toString();
        final base = _host.text.trim().replaceAll(RegExp(r'/+$'), '');
        final url = '$base/live/${Uri.encodeComponent(_username.text.trim())}/'
            '${Uri.encodeComponent(_password.text)}/$id.$extension';
        return Channel(
          name: (map['name'] ?? 'Canal $id').toString(),
          url: url,
          tvgId: map['epg_channel_id']?.toString(),
          logo: map['stream_icon']?.toString(),
          group: map['category_id']?.toString(),
        );
      }).toList();
      if (!mounted) return;
      setState(() {
        _channels = parsed;
        _visible = parsed;
        _selected = null;
        _loading = false;
        _status = '${parsed.length} canais ao vivo carregados via Xtream.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Falha no login Xtream: $e';
      });
    }
  }

  Future<void> _play(Channel channel) async {
    setState(() {
      _selected = channel;
      _status = 'Abrindo ${channel.name}...';
    });
    try {
      await _player.play(channel.url);
      if (mounted) setState(() => _status = 'Reproduzindo: ${channel.name}');
    } catch (e) {
      if (mounted) setState(() => _status = 'Erro ao reproduzir: $e');
    }
  }

  void _filter(String value) {
    final query = value.toLowerCase();
    setState(() {
      _visible = _channels.where((c) =>
        c.name.toLowerCase().contains(query) ||
        (c.group ?? '').toLowerCase().contains(query)
      ).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 800;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AG PLAYER',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
        actions: [
          IconButton(
            tooltip: 'Baixar episódio',
            onPressed: _showDownloadDialog,
            icon: const Icon(Icons.download_for_offline_outlined),
          ),
          IconButton(
            tooltip: 'Parar reprodução',
            onPressed: _player.stop,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _statusBar(),
            Expanded(
              child: isWide
                ? Row(children: [
                    SizedBox(width: 340, child: _sourcesPanel()),
                    Expanded(child: _contentPanel()),
                  ])
                : Column(children: [
                    SizedBox(height: 250, child: _videoPanel()),
                    Expanded(child: _channelPanel()),
                    _compactSources(),
                  ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDownloadDialog() async {
    _downloadUrl.clear();
    _downloadName.clear();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Baixar episódio'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _downloadName,
                decoration: const InputDecoration(
                  labelText: 'Nome do episódio',
                  hintText: 'Série - Temporada 1 - Episódio 1',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _downloadUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'URL direta do episódio',
                  hintText: 'https://servidor/episodio.mp4',
                ),
              ),
              if (_downloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _downloadProgress > 0
                    ? _downloadProgress : null),
                const SizedBox(height: 6),
                Text(_downloadStatus,
                    style: const TextStyle(fontSize: 12)),
              ],
              const SizedBox(height: 8),
              const Text(
                'O download fica salvo no armazenamento privado do aplicativo.',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _downloading ? null : () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
          FilledButton.icon(
            onPressed: _downloading ? null : () async {
              final url = _downloadUrl.text.trim();
              final name = _downloadName.text.trim();
              if (url.isEmpty || name.isEmpty) {
                setState(() => _downloadStatus = 'Informe o nome e a URL.');
                return;
              }
              setState(() {
                _downloading = true;
                _downloadProgress = 0;
                _downloadStatus = 'Iniciando download...';
              });
              try {
                final path = await _downloadService.download(
                  url: url,
                  fileName: name,
                  onProgress: (progress) {
                    if (!mounted) return;
                    setState(() {
                      _downloadProgress = progress.fraction;
                      _downloadStatus = progress.done
                          ? 'Download concluído.'
                          : progress.total > 0
                              ? '${(progress.fraction * 100).toStringAsFixed(0)}% baixado'
                              : 'Baixando episódio...';
                    });
                  },
                );
                if (!mounted) return;
                setState(() {
                  _downloading = false;
                  _downloadStatus = 'Salvo em: $path';
                });
              } catch (e) {
                if (!mounted) return;
                setState(() {
                  _downloading = false;
                  _downloadStatus = 'Falha no download: $e';
                });
              }
            },
            icon: const Icon(Icons.download),
            label: const Text('Baixar'),
          ),
        ],
      ),
    );
  }
