import 'dart:io';

import 'package:native_trend/native_trend.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

Candidate candidate({
  List<String> platforms = const ['ios', 'android'],
  Map<String, String> environment = const {},
}) => Candidate.fromJson(
  package: {
    'name': 'p',
    'latest': {
      'version': '1.0.0',
      'published': '2026-09-01T00:00:00Z',
      'pubspec': {'environment': environment},
    },
  },
  score: {
    'tags': [for (final p in platforms) 'platform:$p'],
  },
  kind: Kind.nativeGlass,
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('native_trend'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('reads platform folders, SDK floors, and dependencies', () {
    for (final p in ['ios', 'android', 'web']) {
      Directory('${dir.path}/$p').createSync();
    }
    File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: app
environment:
  sdk: ^3.9.0
  flutter: ">=3.35.0"
dependencies:
  flutter:
    sdk: flutter
  glassy: ^1.0.0
''');
    final project = Project.read(dir);
    expect(project.hasPubspec, isTrue);
    expect(project.platforms, {'ios', 'android', 'web'});
    expect(project.targets, ['ios', 'android']);
    expect(project.dartFloor, Version(3, 9, 0));
    expect(project.flutterFloor, Version(3, 35, 0));
    expect(project.dependencies, {'glassy'});
  });

  test('an empty folder is an empty project', () {
    final project = Project.read(dir);
    expect(project.hasPubspec, isFalse);
    expect(project.targets, isEmpty);
  });

  test('fitNotes', () {
    final project = Project(
      platforms: {'ios', 'android', 'web'},
      dartFloor: Version(3, 9, 0),
      flutterFloor: Version(3, 35, 0),
    );
    expect(project.fitNotes(candidate()), ['no web support']);
    expect(
      project.fitNotes(
        candidate(
          platforms: ['ios', 'android', 'web'],
          environment: {'sdk': '^3.10.0', 'flutter': '>=3.47.0'},
        ),
      ),
      ['needs Flutter 3.47.0+ / Dart 3.10.0+, project allows 3.35.0 / 3.9.0'],
    );
    // No platform tags (not analyzed yet): nothing to say.
    expect(project.fitNotes(candidate(platforms: [])), isEmpty);
  });

  test('constraintFloor', () {
    expect(constraintFloor('^3.9.0'), Version(3, 9, 0));
    expect(constraintFloor('>=3.35.0 <4.0.0'), Version(3, 35, 0));
    expect(constraintFloor('any'), isNull);
    expect(constraintFloor('nonsense'), isNull);
    expect(constraintFloor(null), isNull);
  });

  test('writeContext and linkContext', () {
    final out = writeContext(dir.path, '.ai/x.md', 'hi');
    expect(out.readAsStringSync(), 'hi');
    expect(linkContext(dir.path, 'CLAUDE.md', '.ai/x.md', 'Glass'), isNotNull);
    expect(linkContext(dir.path, 'CLAUDE.md', '.ai/x.md', 'Glass'), isNull);
    expect(
      File('${dir.path}/CLAUDE.md').readAsStringSync(),
      'Read `.ai/x.md` before adding or changing Glass UI.\n',
    );
  });
}
