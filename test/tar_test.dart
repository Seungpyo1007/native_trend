import 'dart:io';

import 'package:native_trend/native_trend.dart';
import 'package:test/test.dart';

import 'src/fake_pub.dart';

void main() {
  test('readTar reads ustar and pax paths', () {
    for (final pax in [false, true]) {
      final files = readTar(
        gzip.decode(
          tarGz({'lib/a.dart': 'A', 'README.md': 'B'}, paxPaths: pax),
        ),
      ).map((f) => (f.path, String.fromCharCodes(f.bytes)));
      expect(files, [('lib/a.dart', 'A'), ('README.md', 'B')], reason: '$pax');
    }
  });

  test('readTar rejects a truncated archive', () {
    final tar = gzip.decode(tarGz({'lib/a.dart': 'x' * 2000}));
    expect(() => readTar(tar.sublist(0, 1024)).toList(), throwsFormatException);
  });

  test('only source files count', () {
    final text = packageSourceText(
      tarGz({
        'README.md': 'Unlike UiKitView packages, we draw glass ourselves.',
        'example/lib/main.dart': 'UiKitView()',
        'test/a_test.dart': 'UIGlassEffect',
        'lib/src/bar.dart': 'final bar = Bar();',
        'ios/Classes/Bar.swift': 'let e = UIGlassEffect()',
      }),
    );
    expect(text, contains('UIGlassEffect'));
    expect(text, contains('Bar()'));
    expect(text, isNot(contains('UiKitView')));
    expect(isSourcePath('./lib/a.dart'), isTrue);
    expect(isSourcePath('lib/assets/a.png'), isFalse);
  });

  test('stripComments removes comments but keeps strings', () {
    expect(
      stripComments(
        '// UiKitView\n'
        '/// UiKitView docs\n'
        '/* UiKitView /* nested */ still */ a();\n'
        "final url = 'https://x//y'; // UiKitView\n"
        'final s = "/* not a comment */";\n'
        "final t = '''\nmulti // kept\n''';\n",
      ),
      allOf(
        isNot(contains('UiKitView')),
        contains("'https://x//y'"),
        contains('"/* not a comment */"'),
        contains('multi // kept'),
        contains('a();'),
      ),
    );
    // An apostrophe in a comment doesn't open a string.
    expect(stripComments("// don't\nUiKitView"), contains('UiKitView'));
    // An escaped quote doesn't close the string.
    expect(stripComments(r"'a\'b' // c"), r"'a\'b' ");
  });

  test('classification ignores markers that only appear in comments', () {
    final text = packageSourceText(
      tarGz({
        'lib/a.dart': '// Not a UiKitView: we draw it with a shader.\n',
        'ios/Classes/P.swift': '/* someday UIGlassEffect */',
      }),
    );
    expect(classifyGlass(text), Kind.noNativeView);
  });
}
