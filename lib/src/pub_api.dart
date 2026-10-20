import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<Map<String, dynamic>> _getJson(http.Client client, Uri uri) async {
  final res = await client.get(uri);
  if (res.statusCode != 200) {
    throw http.ClientException('HTTP ${res.statusCode}', uri);
  }
  return jsonDecode(res.body) as Map<String, dynamic>;
}

/// Package names from pub.dev search, in pub.dev's ranking order.
Future<List<String>> search(
  http.Client client,
  String query, {
  int pages = 2,
}) async {
  final names = <String>[];
  for (var page = 1; page <= pages; page++) {
    final json = await _getJson(
      client,
      Uri.https('pub.dev', '/api/search', {'q': query, 'page': '$page'}),
    );
    names.addAll([
      for (final p in json['packages'] as List) p['package'] as String,
    ]);
    if (json['next'] == null) break;
  }
  return names;
}

/// Fetches `/api/packages/{name}` and `/api/packages/{name}/score`.
Future<({Map<String, dynamic> package, Map<String, dynamic> score})>
fetchPackage(http.Client client, String name) async {
  final (package, score) = await (
    _getJson(client, Uri.https('pub.dev', '/api/packages/$name')),
    _getJson(client, Uri.https('pub.dev', '/api/packages/$name/score')),
  ).wait;
  return (package: package, score: score);
}

/// Downloads a package archive and returns the ungzipped tar as latin1 text,
/// good enough for substring search without parsing the tar.
///
/// With [cache], archives are kept there by URL. A published pub.dev version
/// never changes, so a cached archive is never refetched.
Future<String> fetchArchiveText(
  http.Client client,
  String archiveUrl, {
  Directory? cache,
}) async {
  final file = cache == null
      ? null
      : File('${cache.path}/${_cacheName(archiveUrl)}');
  if (file != null && file.existsSync()) {
    try {
      return latin1.decode(gzip.decode(file.readAsBytesSync()));
    } on FormatException {
      file.deleteSync(); // Truncated by an interrupted run; fetch again.
    }
  }
  final res = await client.get(Uri.parse(archiveUrl));
  if (res.statusCode != 200) {
    throw http.ClientException('HTTP ${res.statusCode}', res.request?.url);
  }
  final text = latin1.decode(gzip.decode(res.bodyBytes));
  if (file != null) {
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp')..writeAsBytesSync(res.bodyBytes);
    tmp.renameSync(file.path);
  }
  return text;
}

/// The per-user cache directory: `%LOCALAPPDATA%\native_trend` on Windows,
/// otherwise `$XDG_CACHE_HOME/native_trend` or `~/.cache/native_trend`.
/// Null when none of those variables is set.
Directory? defaultCacheDir([Map<String, String>? env]) {
  env ??= Platform.environment;
  final base = Platform.isWindows
      ? env['LOCALAPPDATA']
      : env['XDG_CACHE_HOME'] ??
            (env['HOME'] == null ? null : '${env['HOME']}/.cache');
  return base == null ? null : Directory('$base/native_trend');
}

/// File name for [url]: its last path segment, prefixed with a FNV-1a hash
/// of the whole URL so two hosts serving `a-1.0.0.tar.gz` don't collide.
String _cacheName(String url) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(url)) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  final last = Uri.parse(url).pathSegments.lastOrNull ?? 'archive';
  final safe = last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return '${hash.toRadixString(16).padLeft(8, '0')}-$safe';
}
