import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'tar.dart';

/// A pub.dev response other than 200.
class PubApiException implements Exception {
  PubApiException(this.statusCode, this.uri);

  final int statusCode;
  final Uri uri;

  /// Rate limits and server errors are worth retrying.
  bool get retryable => statusCode == 429 || statusCode >= 500;

  @override
  String toString() => 'HTTP $statusCode from $uri';
}

/// True for errors that mean pub.dev can't be reached right now, as opposed
/// to a problem with one package.
bool isNetworkError(Object e) =>
    e is SocketException ||
    e is TimeoutException ||
    e is http.ClientException ||
    (e is PubApiException && e.retryable);

/// A package's `/api/packages/{name}` and `/api/packages/{name}/score`.
typedef PackageData = ({
  Map<String, dynamic> package,
  Map<String, dynamic> score,
});

/// pub.dev API client with timeouts, retries, and an optional archive cache.
class PubApi {
  PubApi(
    this.client, {
    this.cache,
    this.timeout = const Duration(seconds: 30),
    this.archiveTimeout = const Duration(minutes: 2),
    this.retries = 3,
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? Future<void>.delayed;

  final http.Client client;

  /// Where package archives are kept, or null for no cache.
  final Directory? cache;

  /// Per-request timeout for API calls.
  final Duration timeout;

  /// Per-request timeout for archive downloads, which can be 50 MB.
  final Duration archiveTimeout;

  /// Retries after the first attempt, on network errors, 429, and 5xx.
  final int retries;

  final Future<void> Function(Duration) _sleep;

  /// GET with retries. Backs off 1 s, 2 s, 4 s, ..., or as long as a 429's
  /// `Retry-After` asks.
  Future<http.Response> _get(Uri uri, Duration timeout) async {
    for (var attempt = 0; ; attempt++) {
      Object error;
      Duration? retryAfter;
      try {
        final res = await client.get(uri).timeout(timeout);
        if (res.statusCode == 200) return res;
        final e = PubApiException(res.statusCode, uri);
        if (!e.retryable) throw e;
        error = e;
        final seconds = int.tryParse(res.headers['retry-after'] ?? '');
        if (seconds != null) retryAfter = Duration(seconds: seconds);
      } on SocketException catch (e) {
        error = e;
      } on TimeoutException catch (e) {
        error = e;
      } on http.ClientException catch (e) {
        error = e;
      }
      if (attempt >= retries) throw error;
      await _sleep(retryAfter ?? Duration(seconds: 1 << attempt));
    }
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async =>
      jsonDecode((await _get(uri, timeout)).body) as Map<String, dynamic>;

  /// Package names from pub.dev search, in pub.dev's ranking order.
  Future<List<String>> search(String query, {int pages = 3}) async {
    final names = <String>[];
    for (var page = 1; page <= pages; page++) {
      final json = await _getJson(
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
  Future<PackageData> fetchPackage(String name) async {
    // Future.wait rethrows the first error as is, so callers can catch
    // PubApiException; a record's `.wait` would wrap it.
    final [package, score] = await Future.wait([
      _getJson(Uri.https('pub.dev', '/api/packages/$name')),
      _getJson(Uri.https('pub.dev', '/api/packages/$name/score')),
    ]);
    return (package: package, score: score);
  }

  /// The comment-free source of the latest version of [package] (a
  /// `/api/packages/{name}` response). See [packageSourceText].
  ///
  /// With [cache], the archive is kept there and older archives of the same
  /// package are deleted. A published version never changes, so a cached
  /// archive is never refetched.
  Future<String> fetchSourceText(Map<String, dynamic> package) async {
    final name = package['name'] as String;
    final latest = package['latest'] as Map<String, dynamic>;
    final url = latest['archive_url'] as String;
    final dir = cache;
    final file = dir == null
        ? null
        : File(
            '${dir.path}/${cacheFileName(name, latest['version'] as String, url)}',
          );
    if (file != null && file.existsSync()) {
      try {
        return packageSourceText(file.readAsBytesSync());
      } on FormatException {
        file.deleteSync(); // Truncated by an interrupted run; fetch again.
      }
    }
    final res = await _get(Uri.parse(url), archiveTimeout);
    final text = packageSourceText(res.bodyBytes);
    if (file != null) {
      file.parent.createSync(recursive: true);
      // Unique per process and call, so parallel runs don't clobber it.
      final tmp = File(
        '${file.path}.$pid-${DateTime.now().microsecondsSinceEpoch}.tmp',
      )..writeAsBytesSync(res.bodyBytes);
      tmp.renameSync(file.path);
      pruneCache(dir!, name, keep: file.path);
    }
    return text;
  }
}

/// Cache file name for an archive: `<package>@<version>-<hash>.tar.gz`. The
/// FNV-1a hash of the URL keeps two hosts serving the same version apart.
String cacheFileName(String package, String version, String url) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(url)) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  final safe = version.replaceAll(RegExp(r'[^A-Za-z0-9.+_-]'), '_');
  return '$package@$safe-${hash.toRadixString(16).padLeft(8, '0')}.tar.gz';
}

/// Deletes cached archives of [package] other than [keep], plus files left
/// by native_trend 0.3.0, which named them without the package.
void pruneCache(Directory cache, String package, {required String keep}) {
  for (final f in cache.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (f.path == keep || name.endsWith('.tmp')) continue;
    final at = name.indexOf('@');
    if (at < 0 || name.substring(0, at) == package) {
      try {
        f.deleteSync();
      } on FileSystemException {
        // Another run may have removed it first.
      }
    }
  }
}

/// Deletes [cache] and returns the bytes freed.
int cleanCache(Directory cache) {
  if (!cache.existsSync()) return 0;
  var bytes = 0;
  for (final f in cache.listSync(recursive: true).whereType<File>()) {
    bytes += f.lengthSync();
  }
  cache.deleteSync(recursive: true);
  return bytes;
}

/// The per-user cache directory: `%LOCALAPPDATA%\native_trend` on Windows;
/// elsewhere `$XDG_CACHE_HOME/native_trend` when set, otherwise
/// `~/Library/Caches/native_trend` on macOS and `~/.cache/native_trend` on
/// Linux. Null when the needed variables aren't set.
Directory? defaultCacheDir([Map<String, String>? env, String? os]) {
  env ??= Platform.environment;
  os ??= Platform.operatingSystem;
  final home = env['HOME'];
  final base = switch (os) {
    'windows' => env['LOCALAPPDATA'],
    _ when env['XDG_CACHE_HOME'] != null => env['XDG_CACHE_HOME'],
    'macos' => home == null ? null : '$home/Library/Caches',
    _ => home == null ? null : '$home/.cache',
  };
  return base == null ? null : Directory('$base/native_trend');
}
