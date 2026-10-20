import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:native_trend/native_trend.dart';
import 'package:test/test.dart';

void main() {
  late Directory cache;
  setUp(() => cache = Directory.systemTemp.createTempSync('native_trend'));
  tearDown(() => cache.deleteSync(recursive: true));

  const url = 'https://pub.dev/api/archives/a-1.0.0.tar.gz';
  final archive = gzip.encode(latin1.encode('UiKitView'));

  test('a cached archive is not fetched again', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response.bytes(archive, 200);
    });
    expect(await fetchArchiveText(client, url, cache: cache), 'UiKitView');
    expect(await fetchArchiveText(client, url, cache: cache), 'UiKitView');
    expect(requests, 1);
    expect(cache.listSync().single.path, endsWith('-a-1.0.0.tar.gz'));
  });

  test('a corrupt cache entry is refetched', () async {
    final client = MockClient((_) async => http.Response.bytes(archive, 200));
    await fetchArchiveText(client, url, cache: cache);
    final file = cache.listSync().single as File;
    file.writeAsBytesSync([1, 2, 3]);
    expect(await fetchArchiveText(client, url, cache: cache), 'UiKitView');
    expect(file.readAsBytesSync(), archive);
  });

  test('without a cache nothing is written', () async {
    final client = MockClient((_) async => http.Response.bytes(archive, 200));
    expect(await fetchArchiveText(client, url), 'UiKitView');
    expect(cache.listSync(), isEmpty);
  });

  test('defaultCacheDir', () {
    if (Platform.isWindows) {
      expect(
        defaultCacheDir({'LOCALAPPDATA': r'C:\L'})!.path,
        r'C:\L/native_trend',
      );
    } else {
      expect(
        defaultCacheDir({'XDG_CACHE_HOME': '/x', 'HOME': '/h'})!.path,
        '/x/native_trend',
      );
      expect(defaultCacheDir({'HOME': '/h'})!.path, '/h/.cache/native_trend');
    }
    expect(defaultCacheDir({}), isNull);
  });
}
