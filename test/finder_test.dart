import 'package:native_trend/native_trend.dart';
import 'package:test/test.dart';

import 'src/fake_pub.dart';

final now = DateTime.utc(2026, 10, 21);

FakePackage cupertinoUi({bool glass = false}) => FakePackage(
  'cupertino_ui',
  files: {
    'lib/icons.dart': 'const hourglass = 1;',
    if (glass) 'lib/glass.dart': 'class CupertinoLiquidGlassBar {}',
  },
);

TrendFinder finder(FakePub pub, {Project? project}) => TrendFinder(
  PubApi(pub.client, sleep: (_) async {}),
  project: project,
  clock: () => now,
);

void main() {
  test('iOS: classifies, follows federated plugins, and labels', () async {
    final pub = FakePub(
      [
        cupertinoUi(),
        FakePackage(
          'glass_bar',
          plugin: {
            'ios': {'pluginClass': 'P'},
          },
          files: {
            'lib/bar.dart': 'UiKitView(viewType: "bar")',
            'ios/Classes/Bar.swift': 'UIGlassEffect()',
          },
        ),
        FakePackage(
          'fed',
          plugin: {
            'ios': {'default_package': 'fed_ios'},
          },
          files: {'lib/fed.dart': 'FedPlatform.instance.show();'},
        ),
        FakePackage(
          'fed_ios',
          plugin: {
            'ios': {'pluginClass': 'F', 'dartPluginClass': 'FedIos'},
          },
          files: {
            'lib/fed_ios.dart': 'UiKitView(viewType: "fed")',
            'ios/Classes/F.swift': '.glassEffect(.regular)',
          },
        ),
        FakePackage(
          'android_only',
          plugin: {
            'android': {'pluginClass': 'A'},
          },
        ),
        FakePackage('shader'),
        FakePackage(
          'readme_only',
          plugin: {
            'ios': {'pluginClass': 'R'},
          },
          files: {'README.md': 'Not a UiKitView. No UIGlassEffect.'},
        ),
        FakePackage(
          'old',
          published: '2024-01-01T00:00:00Z',
          plugin: {
            'ios': {'pluginClass': 'O'},
          },
          files: {'lib/o.dart': 'UiKitView() UIGlassEffect'},
          downloads: 99999,
        ),
        FakePackage('gone', discontinued: true),
      ],
      search: {
        glassQuery: [
          'shader',
          'old',
          'android_only',
          'readme_only',
          'fed',
          'glass_bar',
          'gone',
          'missing',
        ],
      },
    );
    final result = await finder(pub).find('ios');
    expect(result.ranked.map((c) => (c.name, c.kind)), [
      ('fed', Kind.nativeGlass),
      ('glass_bar', Kind.nativeGlass),
      ('old', Kind.nativeGlass),
      ('readme_only', Kind.noNativeView),
      ('android_only', Kind.otherPlatform),
      ('shader', Kind.notPlugin),
    ]);
    final fed = result.ranked.first;
    expect(fed.implementation, 'fed_ios');
    expect(result.ranked[2].stale, isTrue);
    expect(result.officialSupport, isFalse);
    expect(result.context, contains('native code in `fed_ios`'));
    expect(result.context, contains('stale: no release since 2024-01-01'));
    expect(result.context, contains('implements Liquid Glass yet'));
    expect(
      renderText(result.ranked),
      contains('plugin for other platforms only'),
    );
    final json = result.toJson();
    expect(json['platform'], 'ios');
    expect(
      (json['candidates'] as List).first,
      containsPair('kind', 'nativeGlass'),
    );
  });

  test('cupertino_ui with Liquid Glass changes the Flutter status', () async {
    final pub = FakePub([cupertinoUi(glass: true)], search: {glassQuery: []});
    final result = await finder(pub).find('ios');
    expect(result.officialSupport, isTrue);
    expect(result.context, contains('now has Liquid Glass widgets'));
  });

  test('an unreachable cupertino_ui is reported as unknown', () async {
    final pub = FakePub([], search: {macosGlassQuery: []});
    final result = await finder(pub).find('macos');
    expect(result.officialSupport, isNull);
    expect(result.context, contains('could not check'));
  });

  test('a failing archive is skipped, not fatal', () async {
    final pub = FakePub(
      [
        cupertinoUi(),
        FakePackage(
          'broken',
          plugin: {
            'ios': {'pluginClass': 'B'},
          },
        ),
      ],
      search: {
        glassQuery: ['broken'],
      },
    );
    // Serve a corrupt archive for broken.
    final api = PubApi(pub.client, sleep: (_) async {});
    final logs = <String>[];
    final result = await TrendFinder(
      _CorruptArchive(api, 'broken'),
      clock: () => now,
      log: logs.add,
    ).find('ios');
    expect(result.ranked, isEmpty);
    expect(logs, contains(startsWith('skip broken:')));
  });

  test('project fit notes', () async {
    final pub = FakePub(
      [
        cupertinoUi(),
        FakePackage(
          'ios_only',
          plugin: {
            'ios': {'pluginClass': 'P'},
          },
          platforms: ['ios'],
          environment: {'flutter': '>=3.47.0'},
          files: {'lib/a.dart': 'UiKitView'},
        ),
      ],
      search: {
        glassQuery: ['ios_only'],
      },
    );
    final project = Project(
      platforms: {'ios', 'android'},
      flutterFloor: constraintFloor('>=3.35.0'),
    );
    final c = (await finder(pub, project: project).find('ios')).ranked.single;
    expect(c.notes, [
      'no android support',
      'needs Flutter 3.47.0+, project allows 3.35.0',
    ]);
  });

  test('android checks material_ui and filters noise', () async {
    final pub = FakePub(
      [
        FakePackage(
          'material_ui',
          files: {
            'lib/theme.dart':
                'class ThemeData {\n  final StyleVariant? styleVariant;\n}\n',
          },
        ),
        FakePackage('fab_m3e', description: 'Expressive FAB'),
        FakePackage('unrelated', description: 'HTTP client'),
      ],
      search: {
        expressiveQueries.first: ['fab_m3e', 'unrelated'],
      },
    );
    final result = await finder(pub).find('android');
    expect(result.ranked.map((c) => c.name), ['material_ui', 'fab_m3e']);
    expect(result.officialSupport, isTrue);
    expect(result.context, contains('The official opt-in is available'));
  });

  test('audit classifies relevant dependencies outside the search', () async {
    final pub = FakePub(
      [
        cupertinoUi(),
        FakePackage(
          'good',
          plugin: {
            'ios': {'pluginClass': 'G'},
          },
          files: {'lib/a.dart': 'UiKitView UIGlassEffect'},
        ),
        FakePackage('glassmorphism', description: 'Frosted glass widgets.'),
        FakePackage('old_glass', description: 'Glass', discontinued: true),
        FakePackage('http', description: 'HTTP client'),
      ],
      search: {
        glassQuery: ['good'],
      },
    );
    final f = finder(pub);
    final deps = {'glassmorphism', 'old_glass', 'http', 'not_on_pub'};
    final data = await f.fetchDeps(deps);
    expect(data.keys, unorderedEquals(['glassmorphism', 'old_glass', 'http']));
    final result = await f.audit('ios', deps, data);
    expect(result.clean, isFalse);
    expect(result.findings.map((x) => (x.name, x.ok)), [
      ('glassmorphism', false),
      ('old_glass', false),
    ]);
    expect(result.findings.first.candidate!.kind, Kind.notPlugin);
    expect(result.findings.first.alternatives.single.name, 'good');
    expect(result.toJson()['findings'], hasLength(2));
  });

  test('audit skips platforms with nothing relevant', () async {
    final pub = FakePub(
      [FakePackage('http', description: 'HTTP client')],
      search: {
        glassQuery: ['good'],
      },
    );
    final f = finder(pub);
    final result = await f.audit('ios', {'http'}, await f.fetchDeps({'http'}));
    expect(result.findings, isEmpty);
    expect(pub.hits.keys, isNot(contains('/api/packages/good')));
  });

  test('archive downloads run at most four at a time', () async {
    final names = [for (var i = 0; i < 9; i++) 'p$i'];
    final pub = FakePub(
      [
        cupertinoUi(),
        for (final n in names)
          FakePackage(
            n,
            plugin: {
              'ios': {'pluginClass': 'P'},
            },
          ),
      ],
      search: {glassQuery: names},
    );
    final api = _CountingApi(PubApi(pub.client, sleep: (_) async {}));
    await TrendFinder(api, clock: () => now).find('ios');
    expect(api.peak, lessThanOrEqualTo(4));
    expect(api.calls, 10, reason: 'nine candidates plus cupertino_ui');
  });
}

/// Fails archive downloads for one package.
class _CorruptArchive implements PubApi {
  _CorruptArchive(this._api, this._name);
  final PubApi _api;
  final String _name;

  @override
  Future<String> fetchSourceText(Map<String, dynamic> package) =>
      package['name'] == _name
      ? Future.error(const FormatException('corrupt'))
      : _api.fetchSourceText(package);

  @override
  dynamic noSuchMethod(Invocation i) => Function.apply(
    switch (i.memberName) {
      #search => _api.search,
      #fetchPackage => _api.fetchPackage,
      _ => throw UnimplementedError('${i.memberName}'),
    },
    i.positionalArguments,
    i.namedArguments,
  );
}

/// Tracks concurrent archive downloads.
class _CountingApi implements PubApi {
  _CountingApi(this._api);
  final PubApi _api;
  var running = 0;
  var peak = 0;
  var calls = 0;

  @override
  Future<String> fetchSourceText(Map<String, dynamic> package) async {
    calls++;
    running++;
    if (running > peak) peak = running;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return await _api.fetchSourceText(package);
    } finally {
      running--;
    }
  }

  @override
  dynamic noSuchMethod(Invocation i) => Function.apply(
    switch (i.memberName) {
      #search => _api.search,
      #fetchPackage => _api.fetchPackage,
      _ => throw UnimplementedError('${i.memberName}'),
    },
    i.positionalArguments,
    i.namedArguments,
  );
}
