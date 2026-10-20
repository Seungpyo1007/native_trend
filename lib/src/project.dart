import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'candidate.dart';

/// The platforms native_trend has a trend for, in output order.
const trendPlatforms = ['ios', 'android', 'macos'];

/// Platforms pub.dev tags packages with.
const pubPlatforms = ['android', 'ios', 'linux', 'macos', 'web', 'windows'];

/// The lowest version [constraint] (a pubspec constraint string) allows, or
/// null when it has none or doesn't parse.
Version? constraintFloor(Object? constraint) {
  if (constraint is! String) return null;
  try {
    final c = VersionConstraint.parse(constraint);
    return c is VersionRange ? c.min : null;
  } on FormatException {
    return null;
  }
}

/// Names under `dependencies` in a pubspec.yaml, without SDK packages such
/// as `flutter`. Dev dependencies are left out: they don't ship UI.
Set<String> pubspecDependencies(String pubspecYaml) {
  final doc = loadYaml(pubspecYaml);
  final deps = doc is Map ? doc['dependencies'] : null;
  return deps is Map
      ? {
          for (final MapEntry(:key, :value) in deps.entries)
            if (!(value is Map && value.containsKey('sdk'))) key.toString(),
        }
      : {};
}

/// What native_trend reads from the Flutter project in `--dir`.
class Project {
  Project({
    this.platforms = const {},
    this.dartFloor,
    this.flutterFloor,
    this.dependencies = const {},
    this.hasPubspec = false,
  });

  /// Reads the platform folders and pubspec.yaml in [dir]. Missing files
  /// give an empty project.
  factory Project.read(Directory dir) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    final yaml = pubspec.existsSync() ? pubspec.readAsStringSync() : null;
    final doc = yaml == null ? null : loadYaml(yaml);
    final env = doc is Map && doc['environment'] is Map
        ? doc['environment'] as Map
        : const {};
    return Project(
      platforms: {
        for (final p in pubPlatforms)
          if (Directory('${dir.path}/$p').existsSync()) p,
      },
      dartFloor: constraintFloor(env['sdk']),
      flutterFloor: constraintFloor(env['flutter']),
      dependencies: yaml == null ? const {} : pubspecDependencies(yaml),
      hasPubspec: yaml != null,
    );
  }

  /// Platform folders present, among [pubPlatforms].
  final Set<String> platforms;

  /// Lowest Dart and Flutter SDKs the project allows.
  final Version? dartFloor;
  final Version? flutterFloor;

  final Set<String> dependencies;
  final bool hasPubspec;

  /// The [trendPlatforms] the project builds for.
  List<String> get targets => [
    for (final p in trendPlatforms)
      if (platforms.contains(p)) p,
  ];

  /// Remarks on how [c] fits: platforms the project builds for that it
  /// doesn't support, and SDK floors above the project's (one note).
  List<String> fitNotes(Candidate c) {
    final sdks = [
      if (_above(c.flutterFloor, flutterFloor))
        ('Flutter ${c.flutterFloor}+', '$flutterFloor'),
      if (_above(c.dartFloor, dartFloor))
        ('Dart ${c.dartFloor}+', '$dartFloor'),
    ];
    return [
      if (c.platforms.isNotEmpty)
        for (final p in pubPlatforms)
          if (platforms.contains(p) && !c.platforms.contains(p))
            'no $p support',
      if (sdks.isNotEmpty)
        'needs ${sdks.map((s) => s.$1).join(' / ')}, project allows '
            '${sdks.map((s) => s.$2).join(' / ')}',
    ];
  }

  static bool _above(Version? package, Version? project) =>
      package != null && project != null && package > project;
}

/// Writes [context] to [rel] under [dir], creating folders.
File writeContext(String dir, String rel, String context) {
  final out = File('$dir/$rel');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(context);
  return out;
}

/// Appends a pointer to [rel] in the file [name] under [dir], unless it
/// already mentions [rel]. Returns the file when it changed.
File? linkContext(String dir, String name, String rel, String topic) {
  final target = File('$dir/$name');
  final text = target.existsSync() ? target.readAsStringSync() : '';
  if (text.contains(rel)) return null;
  final sep = text.isEmpty ? '' : (text.endsWith('\n') ? '\n' : '\n\n');
  target.writeAsStringSync(
    '$text${sep}Read `$rel` before adding or changing $topic UI.\n',
  );
  return target;
}
