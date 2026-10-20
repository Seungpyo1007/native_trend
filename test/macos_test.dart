import 'package:native_trend/native_trend.dart';
import 'package:test/test.dart';

Map<String, dynamic> package(String name, Map<String, dynamic> platforms) => {
  'name': name,
  'latest': {
    'version': '1.0.0',
    'published': '2026-09-01T00:00:00Z',
    'pubspec': {
      'flutter': {
        'plugin': {'platforms': platforms},
      },
    },
  },
};

Candidate candidate(String name, Kind kind) => Candidate.fromJson(
  package: package(name, {'macos': {}}),
  score: {
    'grantedPoints': 160,
    'tags': ['platform:macos'],
  },
  kind: kind,
);

void main() {
  test('isPluginFor checks the macos platform', () {
    expect(isPluginFor(package('a', {'macos': {}}), 'macos'), isTrue);
    expect(isPluginFor(package('b', {'ios': {}}), 'macos'), isFalse);
  });

  test('classify by AppKit markers', () {
    expect(
      classifyGlass('AppKitView ... NSGlassEffectView()', platform: 'macos'),
      Kind.nativeGlass,
    );
    expect(
      classifyGlass('AppKitView ... .glassEffect(.regular)', platform: 'macos'),
      Kind.nativeGlass,
    );
    expect(
      classifyGlass('AppKitView(viewType: "switch")', platform: 'macos'),
      Kind.nativeSystem,
    );
    expect(
      classifyGlass('UiKitView ... UIGlassEffect', platform: 'macos'),
      Kind.noNativeView,
    );
    expect(classifyGlass(null, platform: 'macos'), Kind.notPlugin);
  });

  test('seeds are only seeds', () {
    // Seeded packages get no ranking bonus.
    final ranked = rank([
      candidate(macosGlassSeeds.first, Kind.nativeSystem),
      candidate('other', Kind.nativeGlass),
    ]);
    expect(ranked.first.name, 'other');
  });

  test('macOS context', () {
    final md = renderMacosGlassContext(
      rank([
        candidate('shader', Kind.notPlugin),
        candidate('good', Kind.nativeGlass),
      ]),
      now: DateTime.utc(2026, 10, 21),
    );
    expect(md, contains('Checked against pub.dev on 2026-10-21'));
    expect(md, contains('Recommended: `good`'));
    expect(md, contains('## Do not use (not native macOS views)'));
    expect(md, contains('- `shader`: Flutter-drawn imitation'));
    expect(md, contains('TargetPlatform.macOS'));
    expect(md, contains('MACOSX_DEPLOYMENT_TARGET'));
  });
}
