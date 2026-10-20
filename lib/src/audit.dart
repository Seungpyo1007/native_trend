import 'package:yaml/yaml.dart';

import 'candidate.dart';

/// Names under `dependencies` in a pubspec.yaml. Dev dependencies are left
/// out: they don't ship UI.
Set<String> pubspecDependencies(String pubspecYaml) {
  final doc = loadYaml(pubspecYaml);
  final deps = doc is Map ? doc['dependencies'] : null;
  return deps is Map ? {for (final k in deps.keys) k.toString()} : {};
}

/// One dependency checked against a platform's ranking.
class AuditFinding {
  AuditFinding({
    required this.name,
    this.candidate,
    this.discontinued = false,
    this.replacedBy,
    this.alternatives = const [],
  });

  final String name;

  /// The dependency as ranked, or null when it is discontinued.
  final Candidate? candidate;

  final bool discontinued;

  /// pub.dev's suggested replacement for a discontinued package.
  final String? replacedBy;

  /// The best usable packages the project doesn't already depend on.
  final List<Candidate> alternatives;

  /// True when the dependency is worth keeping.
  bool get ok => !discontinued && candidate!.kind.usable;
}

/// Checks [deps] against one platform's [ranked] candidates. Dependencies
/// that aren't in the ranking are ignored unless listed in [discontinued],
/// which maps each discontinued dependency to pub.dev's replacement, if any.
List<AuditFinding> auditDependencies(
  Set<String> deps,
  List<Candidate> ranked, {
  Map<String, String?> discontinued = const {},
}) {
  final alternatives = [
    for (final c in ranked)
      if (c.kind.usable && !deps.contains(c.name)) c,
  ].take(2).toList();
  return [
    for (final c in ranked)
      if (deps.contains(c.name))
        AuditFinding(
          name: c.name,
          candidate: c,
          alternatives: c.kind.usable ? const [] : alternatives,
        ),
    for (final MapEntry(key: name, value: replacement) in discontinued.entries)
      if (deps.contains(name))
        AuditFinding(
          name: name,
          discontinued: true,
          replacedBy: replacement,
          alternatives: alternatives,
        ),
  ];
}

/// Terminal output for one platform's findings.
String renderAudit(String platform, List<AuditFinding> findings) {
  if (findings.isEmpty) return '$platform: no matching dependencies';
  final b = StringBuffer(platform);
  for (final f in findings) {
    final why = f.discontinued
        ? 'discontinued${f.replacedBy == null ? '' : ', use ${f.replacedBy}'}'
        : f.candidate!.kind.label;
    b.write('\n  ${f.ok ? 'ok   ' : 'skip '}${f.name.padRight(34)} $why');
    if (!f.ok && f.alternatives.isNotEmpty) {
      b.write(
        '\n       instead: ${f.alternatives.map((c) => c.name).join(', ')}',
      );
    }
  }
  return b.toString();
}
