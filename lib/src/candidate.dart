import 'package:pub_semver/pub_semver.dart';

import 'project.dart';

/// How a package delivers the platform's design trend, in ranking order.
///
/// iOS/macOS and Android kinds never mix in one ranking, so the index order
/// is the ranking order within each platform.
enum Kind {
  /// iOS/macOS: native view that calls the OS 26 glass API directly.
  nativeGlass('native view + glass API', usable: true),

  /// iOS/macOS: native view of system controls, which get glass from the
  /// OS 26 SDK.
  nativeSystem('native view, system controls', usable: true),

  /// iOS/macOS: plugin for this platform, but no platform view.
  noNativeView('plugin without a native view'),

  /// iOS/macOS: native plugin, but not for this platform.
  otherPlatform('plugin for other platforms only'),

  /// iOS/macOS: pure Dart, usually a shader imitation.
  notPlugin('Flutter-drawn imitation (no native code)'),

  /// Android: the official flutter.dev Material package.
  official('official flutter.dev package', usable: true),

  /// Android: embeds Jetpack Compose Material 3 views.
  nativeView('native Compose view', usable: true),

  /// Android: Flutter-drawn on top of the official material_ui package.
  onMaterialUi('Flutter-drawn, built on material_ui', usable: true),

  /// Android: Flutter-drawn on the SDK's Material library.
  flutterDrawn('Flutter-drawn', usable: true);

  const Kind(this.label, {this.usable = false});
  final String label;

  /// Worth recommending.
  final bool usable;
}

/// The pubspec `flutter.plugin.platforms` map, or empty.
Map<String, dynamic> pluginPlatforms(Map<String, dynamic> package) {
  final pubspec = package['latest']['pubspec'] as Map<String, dynamic>;
  final flutter = pubspec['flutter'];
  final platforms = flutter is Map && flutter['plugin'] is Map
      ? flutter['plugin']['platforms']
      : null;
  return platforms is Map ? platforms.cast<String, dynamic>() : const {};
}

/// True when the package declares a Flutter plugin for [platform].
bool isPluginFor(Map<String, dynamic> package, String platform) =>
    pluginPlatforms(package)[platform] != null;

/// The endorsed implementation package of a federated plugin for
/// [platform], or null when the package implements it itself.
String? defaultPackage(Map<String, dynamic> package, String platform) {
  final entry = pluginPlatforms(package)[platform];
  if (entry is! Map) return null;
  final implementsItself = [
    'pluginClass',
    'ffiPlugin',
    'dartPluginClass',
  ].any((k) => entry[k] != null);
  final name = entry['default_package'];
  return !implementsItself && name is String ? name : null;
}

/// A release older than this is stale: Liquid Glass and Material 3
/// Expressive APIs change with every OS release.
const staleAfter = Duration(days: 365);

/// A package with pub.dev's numbers.
class Candidate {
  Candidate({
    required this.name,
    required this.version,
    required this.description,
    required this.published,
    required this.kind,
    required this.points,
    required this.likes,
    required this.downloads,
    required this.publisher,
    required this.platforms,
    this.pointsPending = false,
    this.stale = false,
    this.implementation,
    this.dartFloor,
    this.flutterFloor,
    this.notes = const [],
  });

  factory Candidate.fromJson({
    required Map<String, dynamic> package,
    required Map<String, dynamic> score,
    required Kind kind,
    DateTime? now,
    String? implementation,
  }) {
    final latest = package['latest'] as Map<String, dynamic>;
    final pubspec = latest['pubspec'] as Map;
    final environment = pubspec['environment'] as Map? ?? const {};
    final tags = (score['tags'] as List? ?? const []).cast<String>();
    String? tag(String prefix) => tags
        .where((t) => t.startsWith(prefix))
        .map((t) => t.substring(prefix.length))
        .firstOrNull;
    final published = DateTime.parse(latest['published'] as String);
    return Candidate(
      name: package['name'] as String,
      version: latest['version'] as String,
      description: (pubspec['description'] as String? ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
      published: published,
      kind: kind,
      points: score['grantedPoints'] as int? ?? 0,
      // pub.dev reports 0 of 0 until it has analyzed a new release.
      pointsPending: score['maxPoints'] == 0,
      likes: score['likeCount'] as int? ?? 0,
      downloads: score['downloadCount30Days'] as int? ?? 0,
      publisher: tag('publisher:'),
      platforms: [
        for (final t in tags)
          if (t.startsWith('platform:')) t.substring('platform:'.length),
      ],
      stale: (now ?? DateTime.now()).difference(published) > staleAfter,
      implementation: implementation,
      dartFloor: constraintFloor(environment['sdk']),
      flutterFloor: constraintFloor(environment['flutter']),
    );
  }

  final String name;
  final String version;
  final String description;
  final DateTime published;
  final Kind kind;
  final int points;

  /// pub.dev hasn't analyzed this release yet, so [points] is 0 for now.
  final bool pointsPending;
  final int likes;
  final int downloads;
  final String? publisher;
  final List<String> platforms;

  /// No release within [staleAfter].
  final bool stale;

  /// For a federated plugin, the package whose native code was scanned.
  final String? implementation;

  /// Lowest Dart and Flutter SDKs the package allows.
  final Version? dartFloor;
  final Version? flutterFloor;

  /// How the package fits the project, e.g. a missing platform.
  final List<String> notes;

  /// A copy with [notes].
  Candidate withNotes(List<String> notes) => Candidate(
    name: name,
    version: version,
    description: description,
    published: published,
    kind: kind,
    points: points,
    pointsPending: pointsPending,
    likes: likes,
    downloads: downloads,
    publisher: publisher,
    platforms: platforms,
    stale: stale,
    implementation: implementation,
    dartFloor: dartFloor,
    flutterFloor: flutterFloor,
    notes: notes,
  );

  /// The `--json` form. See the README for the schema.
  Map<String, Object?> toJson() => {
    'name': name,
    'version': version,
    'kind': kind.name,
    'label': kind.label,
    'usable': kind.usable,
    'points': pointsPending ? null : points,
    'likes': likes,
    'downloads30Days': downloads,
    'publisher': publisher,
    'platforms': platforms,
    'published': published.toUtc().toIso8601String(),
    'stale': stale,
    'implementation': implementation,
    'notes': notes,
    'description': description,
  };
}

/// By [Kind] order, then fresh before [Candidate.stale], then pub.dev
/// points, then 30-day downloads.
List<Candidate> rank(Iterable<Candidate> all) => all.toList()
  ..sort((a, b) {
    final order = [
      a.kind.index - b.kind.index,
      (a.stale ? 1 : 0) - (b.stale ? 1 : 0),
      b.points - a.points,
      b.downloads - a.downloads,
    ];
    return order.firstWhere((o) => o != 0, orElse: () => 0);
  });

/// `yyyy-mm-dd`.
String dateOf(DateTime d) => d.toIso8601String().substring(0, 10);

/// Stale, federated, and project-fit remarks for [c].
List<String> remarksOf(Candidate c) => [
  if (c.stale) 'stale: no release since ${dateOf(c.published)}',
  if (c.implementation != null) 'native code in `${c.implementation}`',
  ...c.notes,
];

/// One Markdown line describing [c].
String candidateLine(Candidate c) {
  final remarks = remarksOf(c);
  return '`${c.name}` ${c.version} (${c.kind.label}; '
      '${c.pointsPending ? 'pub.dev analysis pending' : '${c.points} pts'}, '
      '${c.likes} likes, ${c.downloads} downloads/30d, '
      '${c.publisher ?? 'unverified'}, last release ${dateOf(c.published)}, '
      'platforms: ${c.platforms.join(', ')})'
      '${remarks.isEmpty ? '' : '. ${remarks.join('; ')}'}';
}

/// Terminal output, ranked.
String renderText(List<Candidate> ranked) => [
  for (final c in ranked)
    '${c.kind.usable ? 'use  ' : 'skip '}'
        '${c.name.padRight(34)} '
        '${c.pointsPending ? '  ?' : c.points.toString().padLeft(3)} pts  '
        '${c.downloads.toString().padLeft(6)} dl/30d  ${c.kind.label}'
        '${remarksOf(c).map((r) => '\n       $r').join()}',
].join('\n');
