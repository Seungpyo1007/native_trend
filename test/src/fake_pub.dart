import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A ustar archive of [files] (path to content), gzipped like pub.dev's.
List<int> tarGz(Map<String, String> files, {bool paxPaths = false}) {
  final out = BytesBuilder();
  void entry(String name, List<int> body, {int type = 0x30}) {
    final h = Uint8List(512);
    void put(int at, String s) =>
        h.setRange(at, at + s.length, latin1.encode(s));
    put(0, name.length > 100 ? name.substring(0, 100) : name);
    put(100, '0000644\x00');
    put(124, '${body.length.toRadixString(8).padLeft(11, '0')}\x00');
    put(136, '00000000000\x00');
    h[156] = type;
    put(257, 'ustar\x00');
    put(263, '00');
    h.setRange(148, 156, latin1.encode('        '));
    final sum = h.fold<int>(0, (a, b) => a + b);
    put(148, '${sum.toRadixString(8).padLeft(6, '0')}\x00 ');
    out
      ..add(h)
      ..add(body)
      ..add(Uint8List((512 - body.length % 512) % 512));
  }

  for (final MapEntry(key: path, value: text) in files.entries) {
    final body = utf8.encode(text);
    if (paxPaths) {
      final record = ' path=$path\n';
      // The length prefix counts itself.
      var len = record.length + 1;
      while ('$len$record'.length != len) {
        len = '$len$record'.length;
      }
      entry('PaxHeaders/x', utf8.encode('$len$record'), type: 0x78);
      entry('ignored-short-name', body);
    } else {
      entry(path, body);
    }
  }
  out.add(Uint8List(1024));
  return gzip.encode(out.toBytes());
}

/// One fake pub.dev package.
class FakePackage {
  FakePackage(
    this.name, {
    this.files = const {},
    this.plugin = const {},
    this.points = 160,
    this.maxPoints = 160,
    this.downloads = 0,
    this.published = '2026-09-01T00:00:00Z',
    this.description = 'A package.',
    this.topics = const [],
    this.platforms = const [],
    this.environment = const {},
    this.dependencies = const {},
    this.discontinued = false,
  });

  final String name;
  final Map<String, String> files;

  /// `flutter.plugin.platforms`; empty for pure Dart.
  final Map<String, Object?> plugin;
  final int points;
  final int maxPoints;
  final int downloads;
  final String published;
  final String description;
  final List<String> topics;
  final List<String> platforms;
  final Map<String, String> environment;
  final Map<String, Object?> dependencies;
  final bool discontinued;

  String get archiveUrl => 'https://pub.dev/api/archives/$name-1.0.0.tar.gz';

  Map<String, Object?> get json => {
    'name': name,
    'isDiscontinued': discontinued,
    'latest': {
      'version': '1.0.0',
      'published': published,
      'archive_url': archiveUrl,
      'pubspec': {
        'name': name,
        'description': description,
        'topics': topics,
        'environment': environment,
        'dependencies': dependencies,
        if (plugin.isNotEmpty)
          'flutter': {
            'plugin': {'platforms': plugin},
          },
      },
    },
  };

  Map<String, Object?> get score => {
    'grantedPoints': points,
    'maxPoints': maxPoints,
    'downloadCount30Days': downloads,
    'likeCount': 0,
    'tags': ['publisher:example.com', for (final p in platforms) 'platform:$p'],
  };
}

/// A MockClient serving [packages], with [search] mapping each query to
/// package names. Counts requests per path in [hits].
class FakePub {
  FakePub(this.packages, {this.search = const {}});

  final List<FakePackage> packages;
  final Map<String, List<String>> search;
  final hits = <String, int>{};

  late final client = MockClient((req) async {
    final path = req.url.path;
    hits[path] = (hits[path] ?? 0) + 1;
    if (path == '/api/search') {
      final names = search[req.url.queryParameters['q']] ?? const [];
      final page = int.parse(req.url.queryParameters['page'] ?? '1');
      return _json({
        'packages': [
          if (page == 1)
            for (final n in names) {'package': n},
        ],
      });
    }
    for (final p in packages) {
      if (path == '/api/packages/${p.name}') return _json(p.json);
      if (path == '/api/packages/${p.name}/score') return _json(p.score);
      if (req.url.toString() == p.archiveUrl) {
        return http.Response.bytes(tarGz(p.files), 200);
      }
    }
    return http.Response('not found', 404);
  });

  static http.Response _json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}
