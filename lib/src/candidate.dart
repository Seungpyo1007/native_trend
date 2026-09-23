/// How a package delivers the platform's design trend, in ranking order.
///
/// iOS and Android kinds never mix in one ranking, so the index order is the
/// ranking order within each platform.
enum Kind {
  /// iOS: native view that calls the iOS 26 glass API directly.
  nativeGlass('native view + glass API', usable: true),

  /// iOS: native view of system controls, which get glass from the iOS 26 SDK.
  nativeSystem('native view, system controls', usable: true),

  /// iOS: plugin, but no platform view.
  noNativeView('plugin without a native view'),

  /// iOS: pure Dart, usually a shader imitation.
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

/// True when the package declares a Flutter plugin for [platform].
bool isPluginFor(Map<String, dynamic> package, String platform) {
  final pubspec = package['latest']['pubspec'] as Map<String, dynamic>;
  final flutter = pubspec['flutter'];
  return flutter is Map &&
      flutter['plugin'] is Map &&
      (flutter['plugin']['platforms'] as Map?)?[platform] != null;
}

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
  });

  factory Candidate.fromJson({
    required Map<String, dynamic> package,
    required Map<String, dynamic> score,
    required Kind kind,
  }) {
    final latest = package['latest'] as Map<String, dynamic>;
    final tags = (score['tags'] as List? ?? const []).cast<String>();
    String? tag(String prefix) => tags
        .where((t) => t.startsWith(prefix))
        .map((t) => t.substring(prefix.length))
        .firstOrNull;
    return Candidate(
      name: package['name'] as String,
      version: latest['version'] as String,
      description: ((latest['pubspec'] as Map)['description'] as String? ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
      published: DateTime.parse(latest['published'] as String),
      kind: kind,
      points: score['grantedPoints'] as int? ?? 0,
      likes: score['likeCount'] as int? ?? 0,
      downloads: score['downloadCount30Days'] as int? ?? 0,
      publisher: tag('publisher:'),
      platforms: [
        for (final t in tags)
          if (t.startsWith('platform:')) t.substring('platform:'.length),
      ],
    );
  }

  final String name;
  final String version;
  final String description;
  final DateTime published;
  final Kind kind;
  final int points;
  final int likes;
  final int downloads;
  final String? publisher;
  final List<String> platforms;
}

/// By [Kind] order, then pub.dev points, then 30-day downloads.
List<Candidate> rank(Iterable<Candidate> all) => all.toList()
  ..sort((a, b) {
    final order = [
      a.kind.index - b.kind.index,
      b.points - a.points,
      b.downloads - a.downloads,
    ];
    return order.firstWhere((o) => o != 0, orElse: () => 0);
  });

/// `yyyy-mm-dd`.
String dateOf(DateTime d) => d.toIso8601String().substring(0, 10);

/// One Markdown line describing [c].
String candidateLine(Candidate c) =>
    '`${c.name}` ${c.version} (${c.kind.label}; ${c.points} pts, '
    '${c.likes} likes, ${c.downloads} downloads/30d, '
    '${c.publisher ?? 'unverified'}, last release ${dateOf(c.published)}, '
    'platforms: ${c.platforms.join(', ')})';

/// Terminal output, ranked.
String renderText(List<Candidate> ranked) => [
  for (final c in ranked)
    '${c.kind.usable ? 'use  ' : 'skip '}'
        '${c.name.padRight(34)} ${c.points.toString().padLeft(3)} pts  '
        '${c.downloads.toString().padLeft(6)} dl/30d  ${c.kind.label}',
].join('\n');
