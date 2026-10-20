import 'audit.dart';
import 'candidate.dart';
import 'expressive.dart';
import 'glass.dart';
import 'pool.dart';
import 'project.dart';
import 'pub_api.dart';

/// One platform's ranking and AI context.
class TrendResult {
  TrendResult({
    required this.platform,
    required this.ranked,
    required this.context,
    this.officialSupport,
  });

  final String platform;
  final List<Candidate> ranked;

  /// Markdown for AI coding assistants.
  final String context;

  /// Android: material_ui's `ThemeData` accepts `styleVariant`. iOS and
  /// macOS: cupertino_ui has Liquid Glass. Null when it couldn't be checked.
  final bool? officialSupport;

  /// The `--json` form. See the README for the schema.
  Map<String, Object?> toJson() => {
    'platform': platform,
    'officialSupport': officialSupport,
    'candidates': [for (final c in ranked) c.toJson()],
  };
}

/// One platform's audit findings.
class AuditResult {
  AuditResult(this.platform, this.findings);

  final String platform;
  final List<AuditFinding> findings;

  bool get clean => findings.every((f) => f.ok);

  /// The `--json` form. See the README for the schema.
  Map<String, Object?> toJson() => {
    'platform': platform,
    'findings': [for (final f in findings) f.toJson()],
  };
}

/// Finds, classifies, and ranks packages, and audits dependencies.
class TrendFinder {
  TrendFinder(
    this.api, {
    this.project,
    this.pages = 3,
    this.concurrency = 4,
    DateTime Function()? clock,
    void Function(String)? log,
  }) : _clock = clock ?? DateTime.now,
       _log = log ?? ((_) {});

  final PubApi api;

  /// The project to annotate candidates for, or null for none.
  final Project? project;

  /// pub.dev search pages per query.
  final int pages;

  /// Package and archive downloads in flight at once.
  final int concurrency;

  final DateTime Function() _clock;
  final void Function(String) _log;

  /// Package names worth fetching for [platform], before any filtering.
  Future<Set<String>> candidateNames(String platform) async =>
      switch (platform) {
        'ios' => {...await api.search(glassQuery, pages: pages)},
        'macos' => {
          ...macosGlassSeeds,
          ...await api.search(macosGlassQuery, pages: pages),
        },
        'android' => {
          officialMaterial,
          for (final q in expressiveQueries)
            ...await api.search(q, pages: pages),
        },
        _ => throw ArgumentError.value(platform, 'platform'),
      };

  /// Ranks [platform]'s packages and renders its context.
  Future<TrendResult> find(String platform) async {
    final names = await candidateNames(platform);
    var fetched = await _fetchAll(names);
    if (platform == 'android') {
      fetched = [
        for (final r in fetched)
          if (r.package['name'] == officialMaterial ||
              isExpressiveRelated(r.package))
            r,
      ];
    }
    bool? official;
    final candidates = await mapPool(fetched, concurrency, (r) async {
      try {
        final (candidate, source) = await _classify(platform, r);
        if (r.package['name'] == officialMaterial && source != null) {
          official = styleVariantWired(source);
        }
        return candidate;
      } on Exception catch (e) {
        // One bad archive shouldn't sink the run; pub.dev being down fails
        // the search or package fetches instead.
        _log('skip ${r.package['name']}: $e');
        return null;
      }
    });
    // After the pool, so downloads stay within [concurrency].
    if (platform != 'android') official = await _cupertinoGlass();
    final ranked = rank(candidates.nonNulls);
    final now = _clock();
    return TrendResult(
      platform: platform,
      ranked: ranked,
      officialSupport: official,
      context: switch (platform) {
        'ios' => renderGlassContext(ranked, now: now, officialGlass: official),
        'macos' => renderMacosGlassContext(
          ranked,
          now: now,
          officialGlass: official,
        ),
        _ => renderExpressiveContext(
          ranked,
          officialOptIn: official ?? false,
          now: now,
        ),
      },
    );
  }

  /// Audits [deps] for [platform]. Dependencies are checked when they show
  /// up in the ranking or look relevant by name, description, or topics.
  /// [depData] holds the dependencies' pub.dev data, from [fetchDeps].
  Future<AuditResult> audit(
    String platform,
    Set<String> deps,
    Map<String, PackageData> depData,
  ) async {
    final names = await candidateNames(platform);
    final relevant = {
      for (final MapEntry(:key, :value) in depData.entries)
        if (names.contains(key) || _looksRelevant(platform, value.package)) key,
    };
    if (relevant.isEmpty) return AuditResult(platform, const []);
    final result = await find(platform);
    final ranks = {for (final c in result.ranked) c.name};
    final discontinued = <String, String?>{};
    final direct = <Candidate>[];
    for (final name in relevant.difference(ranks)) {
      final r = depData[name]!;
      if (r.package['isDiscontinued'] == true) {
        discontinued[name] = r.package['replacedBy'] as String?;
      } else if (_looksRelevant(platform, r.package)) {
        try {
          direct.add((await _classify(platform, r)).$1);
        } on Exception catch (e) {
          _log('skip $name: $e');
        }
      }
      // Otherwise it is search noise the ranking filtered out.
    }
    return AuditResult(
      platform,
      auditDependencies(
        deps,
        result.ranked,
        direct: direct,
        discontinued: discontinued,
      ),
    );
  }

  /// pub.dev data for [deps], skipping packages that aren't on pub.dev.
  Future<Map<String, PackageData>> fetchDeps(Set<String> deps) async {
    final fetched = await mapPool(deps, concurrency, (name) async {
      try {
        return await api.fetchPackage(name);
      } on PubApiException catch (e) {
        if (e.retryable) rethrow;
        _log('skip $name: not on pub.dev');
        return null;
      }
    });
    return {for (final r in fetched.nonNulls) r.package['name'] as String: r};
  }

  static bool _looksRelevant(String platform, Map<String, dynamic> package) {
    if (platform == 'android') return isExpressiveRelated(package);
    final pubspec = package['latest']['pubspec'] as Map<String, dynamic>;
    final text = [
      package['name'],
      pubspec['description'] ?? '',
      ...(pubspec['topics'] as List? ?? const []),
    ].join(' ').toLowerCase();
    return text.contains('glass');
  }

  /// Whether cupertino_ui has Liquid Glass, or null when unknown.
  Future<bool?> _cupertinoGlass() async {
    try {
      final r = await api.fetchPackage(officialCupertino);
      return cupertinoGlassShipped(await _source(r.package));
    } on Exception catch (e) {
      _log('could not check $officialCupertino: $e');
      return null;
    }
  }

  /// Classifies one package for [platform]. Also returns the scanned source,
  /// or null when there was nothing to scan.
  Future<(Candidate, String?)> _classify(String platform, PackageData r) async {
    final package = r.package;
    final isOfficial = package['name'] == officialMaterial;
    String? source;
    String? implementation;
    if (isOfficial) {
      source = await _source(package);
    } else if (isPluginFor(package, platform)) {
      source = await _source(package);
      implementation = defaultPackage(package, platform);
      if (implementation != null) {
        // Federated: the app-facing package has no native code of its own.
        final impl = await api.fetchPackage(implementation);
        source = '$source\n${await _source(impl.package)}';
      }
    }
    final kind = platform == 'android'
        ? classifyExpressive(package, archiveText: source)
        : classifyGlass(
            source,
            platform: platform,
            pluginElsewhere: pluginPlatforms(package).isNotEmpty,
          );
    var candidate = Candidate.fromJson(
      package: package,
      score: r.score,
      kind: kind,
      now: _clock(),
      implementation: implementation,
    );
    final p = project;
    if (p != null) candidate = candidate.withNotes(p.fitNotes(candidate));
    return (candidate, source);
  }

  Future<String> _source(Map<String, dynamic> package) {
    _log('scanning ${package['name']} ...');
    return api.fetchSourceText(package);
  }

  /// Fetches pub.dev data for [names], dropping failures and discontinued
  /// ones.
  Future<List<PackageData>> _fetchAll(Iterable<String> names) async {
    final fetched = await mapPool(names, concurrency, (n) async {
      try {
        return await api.fetchPackage(n);
      } on PubApiException catch (e) {
        if (e.retryable) rethrow;
        _log('skip $n: $e');
        return null;
      }
    });
    return [
      for (final r in fetched.nonNulls)
        if (r.package['isDiscontinued'] != true) r,
    ];
  }
}
