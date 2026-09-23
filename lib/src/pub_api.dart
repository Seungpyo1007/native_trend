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
Future<String> fetchArchiveText(http.Client client, String archiveUrl) async {
  final res = await client.get(Uri.parse(archiveUrl));
  if (res.statusCode != 200) {
    throw http.ClientException('HTTP ${res.statusCode}', res.request?.url);
  }
  return latin1.decode(gzip.decode(res.bodyBytes));
}
