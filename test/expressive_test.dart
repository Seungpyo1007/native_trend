import 'package:native_trend/native_trend.dart';
import 'package:test/test.dart';

Map<String, dynamic> package(
  String name, {
  String description = 'A Material 3 Expressive button.',
  List<String> topics = const [],
  Map<String, dynamic> deps = const {},
}) => {
  'name': name,
  'latest': {
    'version': '1.0.0',
    'published': '2026-09-01T00:00:00Z',
    'pubspec': {
      'description': description,
      'topics': topics,
      'dependencies': deps,
    },
  },
};

Candidate candidate(String name, Kind kind, {int points = 160}) =>
    Candidate.fromJson(
      package: package(name),
      score: {'grantedPoints': points, 'tags': <String>[]},
      kind: kind,
    );

void main() {
  test('relevance filter keeps Expressive packages only', () {
    expect(isExpressiveRelated(package('fab_m3e', description: 'FAB')), isTrue);
    expect(isExpressiveRelated(package('a', topics: ['m3e'])), isTrue);
    expect(
      isExpressiveRelated(package('mix', description: 'Styling')),
      isFalse,
    );
  });

  test('classifyExpressive', () {
    expect(classifyExpressive(package('material_ui')), Kind.official);
    expect(
      classifyExpressive(
        package('compose_m3e'),
        archiveText: 'AndroidView(...) import androidx.compose.material3.*',
      ),
      Kind.nativeView,
    );
    expect(
      classifyExpressive(package('a', deps: {'material_ui': '^1.4.0'})),
      Kind.onMaterialUi,
    );
    expect(classifyExpressive(package('b')), Kind.flutterDrawn);
  });

  test('styleVariantWired detects the ThemeData field, not the enum', () {
    expect(styleVariantWired('enum StyleVariant { material3 }'), isFalse);
    expect(styleVariantWired('final StyleVariant? styleVariant;'), isTrue);
    expect(styleVariantWired('StyleVariant get styleVariant =>'), isTrue);
  });

  test('rank: official, native, on material_ui, then the rest', () {
    final ranked = rank([
      candidate('drawn', Kind.flutterDrawn, points: 160),
      candidate('on_mui', Kind.onMaterialUi, points: 100),
      candidate('material_ui', Kind.official),
      candidate('native', Kind.nativeView),
    ]);
    expect(ranked.map((c) => c.name), [
      'material_ui',
      'native',
      'on_mui',
      'drawn',
    ]);
  });

  test('context switches on the official opt-in', () {
    final ranked = rank([candidate('material_ui', Kind.official)]);
    expect(
      renderExpressiveContext(ranked, officialOptIn: false),
      contains('does not accept a `styleVariant` yet'),
    );
    expect(
      renderExpressiveContext(ranked, officialOptIn: true),
      contains('The official opt-in is available'),
    );
  });
}
