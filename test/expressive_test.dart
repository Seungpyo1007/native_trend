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
    String theme(String body) =>
        'class ThemeData with Diagnosticable {\n'
        '$body\n}\nenum StyleVariant { material3 }\n';
    expect(styleVariantWired(theme('final Brightness brightness;')), isFalse);
    expect(
      styleVariantWired(theme('final StyleVariant? styleVariant;')),
      isTrue,
    );
    expect(
      styleVariantWired(theme('StyleVariant get styleVariant =>')),
      isTrue,
    );
  });

  test('styleVariantWired ignores widgets with their own styleVariant', () {
    // material_ui 1.7.0 and 1.8.0: IconButton has the field, ThemeData doesn't.
    const source =
        'class ThemeData with Diagnosticable {\n'
        '  final Brightness brightness;\n}\n'
        'class _IconButtonM3 extends StatelessWidget {\n'
        '  final StyleVariant styleVariant;\n}\n';
    expect(styleVariantWired(source), isFalse);
    expect(styleVariantWired('final StyleVariant? styleVariant;'), isFalse);
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
