import 'package:native_trend/native_trend.dart';
import 'package:test/test.dart';

Map<String, dynamic> package(String name, {bool iosPlugin = true}) => {
  'name': name,
  'latest': {
    'version': '1.0.0',
    'published': '2026-09-01T00:00:00Z',
    'pubspec': {
      if (iosPlugin)
        'flutter': {
          'plugin': {
            'platforms': {
              'ios': {'pluginClass': 'P'},
            },
          },
        }
      else
        'flutter': {
          'shaders': ['shaders/glass.frag'],
        },
    },
  },
};

Candidate candidate(String name, Kind kind, {int points = 160, int dl = 0}) =>
    Candidate.fromJson(
      package: package(name),
      score: {
        'grantedPoints': points,
        'downloadCount30Days': dl,
        'tags': ['publisher:example.com', 'platform:ios'],
      },
      kind: kind,
    );

void main() {
  test('isIosPlugin reads the pubspec', () {
    expect(isIosPlugin(package('a')), isTrue);
    expect(isIosPlugin(package('b', iosPlugin: false)), isFalse);
  });

  test('classify by archive markers', () {
    expect(
      classify('UiKitView(...) let e = UIGlassEffect()'),
      Kind.nativeGlass,
    );
    expect(classify('AppKitView ... .glassEffect(.regular)'), Kind.nativeGlass);
    expect(classify('UiKitView(viewType: "tabbar")'), Kind.nativeSystem);
    expect(classify('MethodChannel only'), Kind.noNativeView);
    expect(classify(null), Kind.notPlugin);
  });

  test('rank puts native glass first, then points, then downloads', () {
    final ranked = rank([
      candidate('shader', Kind.notPlugin, dl: 99999),
      candidate('system', Kind.nativeSystem),
      candidate('glass_low', Kind.nativeGlass, points: 150),
      candidate('glass_high_dl', Kind.nativeGlass, dl: 10),
      candidate('glass_low_dl', Kind.nativeGlass, dl: 1),
    ]);
    expect(ranked.map((c) => c.name), [
      'glass_high_dl',
      'glass_low_dl',
      'glass_low',
      'system',
      'shader',
    ]);
  });

  test('context recommends the top native and lists skipped', () {
    final md = renderContext(
      rank([
        candidate('shader', Kind.notPlugin),
        candidate('good', Kind.nativeGlass),
      ]),
    );
    expect(md, contains('Recommended: `good`'));
    expect(md, contains('- `shader`: Flutter-drawn imitation'));
  });
}
