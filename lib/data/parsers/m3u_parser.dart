import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import '../../domain/entities/channel.dart';

class M3uParser {
  static Future<List<Channel>> parse(String content) async {
    if (content.trim().isEmpty) return <Channel>[];
    return Isolate.run(() => _parseInIsolate(content));
  }
}

List<Channel> _parseInIsolate(String content) {
  final result = <Channel>[];
  String? name;
  Map<String, String> attrs = {};

  for (final raw in LineSplitter.split(content)) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    if (line.startsWith('#EXTINF:')) {
      final sep = _commaOutsideQuotes(line);
      if (sep < 0) {
        name = null;
        attrs = {};
        continue;
      }
      final meta = line.substring(0, sep);
      final title = line.substring(sep + 1).trim();
      attrs = _attributes(meta);
      name = title.isEmpty ? 'Canal sem nome' : title;
      continue;
    }

    if (line.startsWith('#EXTGRP:')) {
      attrs['group-title'] = line.substring(8).trim();
      continue;
    }

    if (line.startsWith('#')) continue;

    final validScheme = line.startsWith('http://') ||
        line.startsWith('https://') ||
        line.startsWith('rtmp://') ||
        line.startsWith('rtsp://');
    if (name != null && validScheme) {
      result.add(Channel(
        name: name,
        url: line,
        tvgId: attrs['tvg-id'],
        logo: attrs['tvg-logo'],
        group: attrs['group-title'],
      ));
    }
    name = null;
    attrs = {};
  }
  return result;
}

int _commaOutsideQuotes(String line) {
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    if (line[i] == '"') quoted = !quoted;
    if (line[i] == ',' && !quoted) return i;
  }
  return -1;
}

Map<String, String> _attributes(String meta) {
  final map = <String, String>{};
  final re = RegExp(r'([\w-]+)="([^"]*)"');
  for (final m in re.allMatches(meta)) {
    map[m.group(1)!.toLowerCase()] = m.group(2)!;
  }
  return map;
}
