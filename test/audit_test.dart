import 'package:native_trend/native_trend.dart';
import 'package:test/test.dart';

Candidate candidate(String name, Kind kind) => Candidate.fromJson(
  package: {
    'name': name,
    'latest': {
      'version': '1.0.0',
      'published': '2026-09-01T00:00:00Z',
      'pubspec': <String, dynamic>{},
    },
  },
  score: {'grantedPoints': 160, 'tags': <String>[]},
  kind: kind,
);

void main() {
  test('pubspecDependencies reads dependencies only', () {
    const yaml = '''
name: app
dependencies:
  flutter:
    sdk: flutter
  liquid_glass_renderer: ^0.2.0
dev_dependencies:
  test: any
''';
    expect(pubspecDependencies(yaml), {'flutter', 'liquid_glass_renderer'});
    expect(pubspecDependencies('name: app'), isEmpty);
  });

  final ranked = rank([
    candidate('native_a', Kind.nativeGlass),
    candidate('native_b', Kind.nativeGlass),
    candidate('native_c', Kind.nativeSystem),
    candidate('shader', Kind.notPlugin),
  ]);

  test('flags skipped dependencies with alternatives', () {
    final findings = auditDependencies({'shader', 'native_a', 'http'}, ranked);
    expect(findings.map((f) => (f.name, f.ok)), [
      ('native_a', true),
      ('shader', false),
    ]);
    // native_a is already a dependency, so it isn't suggested.
    expect(findings.last.alternatives.map((c) => c.name), [
      'native_b',
      'native_c',
    ]);
  });

  test('flags discontinued dependencies', () {
    final findings = auditDependencies(
      {'old'},
      ranked,
      discontinued: {'old': 'native_a'},
    );
    expect(findings.single.ok, isFalse);
    expect(
      renderAudit('ios', findings),
      contains('discontinued, use native_a'),
    );
  });

  test('renders an empty platform', () {
    expect(renderAudit('macos', const []), 'macos: no matching dependencies');
  });
}
