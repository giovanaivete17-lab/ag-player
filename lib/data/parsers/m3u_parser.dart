import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import '../../domain/entities/channel.dart';

class M3uParser {
  static Future<List<Channel>> parse(String content) async {
    if (content.trim().isEmpty) return const [];
    return Isolate.run(() => _parseInIsolate(content));
  }
}

List<Channel> _parseInIsolate(String content) {
  final result = <Channel>[];
  String? name;
  Map<String, String> attributes = {};

  for (final raw in const LineSplitter().split(content)) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    if (line.startsWith('#EXTINF:')) {
      final separator = _commaOutsideQuotes(line);
      if (separator < 0) {
        name = null;
        attributes = {};
        continue;
      }
      final metadata = line.substring(0, separator);
      name = line.substring(separator + 1).trim();
      attributes = _attributes(metadata);
      if (name.isEmpty) name = 'Canal sem nome';
      continue;
    }

    if (line.startsWith('#EXTGRP:')) {
      attributes['group-title'] = line.substring(8).trim();
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
        tvgId: attributes['tvg-id'],
        logo: attributes['tvg-logo'],
        group: attributes['group-title'],
      ));
    }
    name = null;
    attributes = {};
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

Map<String, String> _attributes(String source) {
  final values = <String, String>{};
  final pattern = RegExp(r'''([\w-]+)\s*=\s*("(?:[^"\\]|\\.)*"|[^\s]+)''');
  for (final match in pattern.allMatches(source)) {
    var value = match.group(2)!;
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    values[match.group(1)!] = value;
  }
  return values;
}
