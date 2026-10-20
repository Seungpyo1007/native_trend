import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:native_trend/native_trend.dart';
import 'package:test/test.dart';

import 'src/fake_pub.dart';

Map<String, dynamic> package(String name, String version) => {
  'name': name,
  'latest': {
    'version': version,
    'archive_url': 'https://pub.dev/api/archives/$name-$version.tar.gz',
  },
};

void main() {
  late Directory cache;
  setUp(() => cache = Directory.systemTemp.createTempSync('native_trend'));
  tearDown(() => cache.deleteSync(recursive: true));

  final archive = tarGz({'lib/a.dart': 'UiKitView'});

  test('a cached archive is not fetched again', () async {
    var requests = 0;
    final api = PubApi(
      MockClient((_) async {
        requests++;
        return http.Response.bytes(archive, 200);
      }),
      cache: cache,
    );
    final a = package('a', '1.0.0');
    expect(await api.fetchSourceText(a), contains('UiKitView'));
    expect(await api.fetchSourceText(a), contains('UiKitView'));
    expect(requests, 1);
    expect(cache.listSync().single.path, contains('a@1.0.0-'));
  });

  test('a corrupt cache entry is refetched', () async {
    final api = PubApi(
      MockClient((_) async => http.Response.bytes(archive, 200)),
      cache: cache,
    );
    final a = package('a', '1.0.0');
    await api.fetchSourceText(a);
    final file = cache.listSync().single as File;
    file.writeAsBytesSync([1, 2, 3]);
    expect(await api.fetchSourceText(a), contains('UiKitView'));
    expect(file.readAsBytesSync(), archive);
  });

  test('only the newest archive per package is kept', () async {
    File('${cache.path}/0123abcd-old-0.1.0.tar.gz').writeAsStringSync('0.3.0');
    File('${cache.path}/x.tmp').writeAsStringSync('another run');
    final api = PubApi(
      MockClient((_) async => http.Response.bytes(archive, 200)),
      cache: cache,
    );
    await api.fetchSourceText(package('a', '1.0.0'));
    await api.fetchSourceText(package('ab', '1.0.0'));
    await api.fetchSourceText(package('a', '1.1.0'));
    final names = cache.listSync().map((f) => f.uri.pathSegments.last);
    expect(names, hasLength(3));
    expect(names.where((n) => n.startsWith('a@1.1.0-')), hasLength(1));
    expect(names.where((n) => n.startsWith('ab@1.0.0-')), hasLength(1));
    expect(names, contains('x.tmp'));
  });

  test('without a cache nothing is written', () async {
    final api = PubApi(
      MockClient((_) async => http.Response.bytes(archive, 200)),
    );
    expect(await api.fetchSourceText(package('a', '1.0.0')), isNotEmpty);
    expect(cache.listSync(), isEmpty);
  });

  test('cleanCache deletes the folder', () {
    File('${cache.path}/a').writeAsStringSync('12345');
    expect(cleanCache(cache), 5);
    expect(cache.existsSync(), isFalse);
    expect(cleanCache(cache), 0);
    cache.createSync(); // for tearDown
  });

  group('retries', () {
    final delays = <Duration>[];
    setUp(delays.clear);
    PubApi api(MockClientHandler handler, {int retries = 3}) => PubApi(
      MockClient(handler),
      retries: retries,
      timeout: const Duration(milliseconds: 50),
      sleep: (d) async => delays.add(d),
    );

    test('on 5xx and 429, with backoff and Retry-After', () async {
      final codes = [503, 429, 200];
      final names = await api((_) async {
        final code = codes.removeAt(0);
        return http.Response(
          code == 200 ? '{"packages": [{"package": "a"}]}' : 'busy',
          code,
          headers: {if (code == 429) 'retry-after': '7'},
        );
      }).search('q', pages: 1);
      expect(names, ['a']);
      expect(delays, [const Duration(seconds: 1), const Duration(seconds: 7)]);
    });

    test('on timeouts and socket errors, then gives up', () async {
      var calls = 0;
      final f = api((_) async {
        calls++;
        if (calls.isOdd) throw const SocketException('down');
        return Completer<http.Response>().future; // never answers
      }, retries: 2).search('q');
      await expectLater(f, throwsA(isA<SocketException>()));
      expect(calls, 3);
      expect(delays, [const Duration(seconds: 1), const Duration(seconds: 2)]);
    });

    test('not on 404', () async {
      var calls = 0;
      final f = api((_) async {
        calls++;
        return http.Response('no', 404);
      }).fetchPackage('missing');
      await expectLater(
        f,
        throwsA(
          isA<PubApiException>().having((e) => e.retryable, 'retryable', false),
        ),
      );
      expect(calls, 2, reason: 'package and score requests, once each');
    });

    test('isNetworkError', () {
      expect(isNetworkError(TimeoutException('t')), isTrue);
      expect(isNetworkError(PubApiException(503, Uri())), isTrue);
      expect(isNetworkError(PubApiException(404, Uri())), isFalse);
      expect(isNetworkError(const FormatException()), isFalse);
    });
  });

  test('defaultCacheDir', () {
    expect(
      defaultCacheDir({'LOCALAPPDATA': r'C:\L'}, 'windows')!.path,
      r'C:\L/native_trend',
    );
    expect(
      defaultCacheDir({'XDG_CACHE_HOME': '/x', 'HOME': '/h'}, 'macos')!.path,
      '/x/native_trend',
    );
    expect(
      defaultCacheDir({'HOME': '/h'}, 'macos')!.path,
      '/h/Library/Caches/native_trend',
    );
    expect(
      defaultCacheDir({'HOME': '/h'}, 'linux')!.path,
      '/h/.cache/native_trend',
    );
    expect(defaultCacheDir({}, 'linux'), isNull);
  });
}
