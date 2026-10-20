import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:native_trend/native_trend.dart';

const _usage = '''
Usage: native_trend find [options]
       native_trend audit [options]

find: finds the pub.dev packages that best follow the platform's design
trend, prints them ranked, and writes an AI context file.
  ios:     Liquid Glass plugins that use real native iOS views
  macos:   Liquid Glass plugins that use real native AppKit views
  android: Material 3 Expressive, official material_ui first

audit: checks the project's dependencies against the same rankings and
exits with 1 when one should be replaced.
''';

const _platforms = ['ios', 'android', 'macos'];
const _cacheHelp =
    'Keep downloaded package archives in the user cache directory.';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand(
      'find',
      ArgParser()
        ..addOption('platform', allowed: _platforms, defaultsTo: 'ios')
        ..addOption('dir', defaultsTo: '.', help: 'Project root.')
        ..addFlag('cache', defaultsTo: true, help: _cacheHelp)
        ..addOption(
          'out',
          help: 'Output path. Default: .ai/native_trend_<platform>.md',
        )
        ..addMultiOption(
          'link',
          help:
              'Add a pointer to the output in these files, '
              'e.g. AGENTS.md or CLAUDE.md.',
        ),
    )
    ..addCommand(
      'audit',
      ArgParser()
        ..addMultiOption(
          'platform',
          allowed: _platforms,
          defaultsTo: _platforms,
        )
        ..addOption('dir', defaultsTo: '.', help: 'Project root.')
        ..addFlag('cache', defaultsTo: true, help: _cacheHelp),
    );

  final ArgResults opts;
  try {
    opts = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n$_usage\n${parser.usage}');
    exit(64);
  }
  final cmd = opts.command;
  if (opts.flag('help') || cmd == null) {
    stdout.writeln('$_usage\n${parser.usage}');
    return;
  }

  final dir = cmd.option('dir')!;
  final cache = cmd.flag('cache') ? defaultCacheDir() : null;
  Set<String>? deps;
  if (cmd.name == 'audit') {
    final pubspec = File('$dir/pubspec.yaml');
    if (!pubspec.existsSync()) {
      stderr.writeln('No pubspec.yaml in $dir');
      exit(66);
    }
    deps = pubspecDependencies(pubspec.readAsStringSync());
  }
  final client = http.Client();
  try {
    if (deps == null) {
      await _findAndWrite(client, cache, cmd, dir);
    } else if (!await _audit(
      client,
      cache,
      deps,
      cmd.multiOption('platform'),
    )) {
      exitCode = 1;
    }
  } finally {
    client.close();
  }
}

Future<void> _findAndWrite(
  http.Client client,
  Directory? cache,
  ArgResults cmd,
  String dir,
) async {
  final platform = cmd.option('platform')!;
  final (ranked, context) = await _find(client, cache, platform);
  stdout.writeln(renderText(ranked));

  final rel = cmd.option('out') ?? '.ai/native_trend_$platform.md';
  final out = File('$dir/$rel');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(context);
  stdout.writeln('\nWrote ${out.path}');
  final topic = platform == 'android'
      ? 'Material 3 Expressive'
      : 'Liquid Glass';
  for (final name in cmd.multiOption('link')) {
    final target = File('$dir/$name');
    final text = target.existsSync() ? target.readAsStringSync() : '';
    if (text.contains(rel)) continue;
    final sep = text.isEmpty ? '' : (text.endsWith('\n') ? '\n' : '\n\n');
    target.writeAsStringSync(
      '$text${sep}Read `$rel` before adding or changing $topic UI.\n',
    );
    stdout.writeln('Linked from ${target.path}');
  }
}

/// Returns true when every matching dependency is worth keeping.
Future<bool> _audit(
  http.Client client,
  Directory? cache,
  Set<String> deps,
  List<String> platforms,
) async {
  var clean = true;
  for (final platform in platforms) {
    final matched = (await _candidateNames(
      client,
      platform,
    )).intersection(deps);
    if (matched.isEmpty) {
      stdout.writeln(renderAudit(platform, const []));
      continue;
    }
    final (ranked, _) = await _find(client, cache, platform);
    final ranks = {for (final c in ranked) c.name};
    // Unranked matches are either search noise or discontinued.
    final discontinued = <String, String?>{};
    for (final name in matched.difference(ranks)) {
      try {
        final r = await fetchPackage(client, name);
        if (r.package['isDiscontinued'] == true) {
          discontinued[name] = r.package['replacedBy'] as String?;
        }
      } on Exception catch (e) {
        stderr.writeln('skip $name: $e');
      }
    }
    final findings = auditDependencies(
      deps,
      ranked,
      discontinued: discontinued,
    );
    stdout.writeln(renderAudit(platform, findings));
    if (findings.any((f) => !f.ok)) clean = false;
  }
  return clean;
}

/// Package names worth fetching for [platform], before any filtering.
Future<Set<String>> _candidateNames(
  http.Client client,
  String platform,
) async => switch (platform) {
  'ios' => {...await search(client, glassQuery)},
  'macos' => {...macosGlassSeeds, ...await search(client, macosGlassQuery)},
  _ => {
    officialMaterial,
    for (final q in expressiveQueries) ...await search(client, q),
  },
};

Future<(List<Candidate>, String)> _find(
  http.Client client,
  Directory? cache,
  String platform,
) => platform == 'android'
    ? _expressive(client, cache)
    : _glass(client, cache, platform);

Future<(List<Candidate>, String)> _glass(
  http.Client client,
  Directory? cache,
  String platform,
) async {
  final names = await _candidateNames(client, platform);
  final out = <Candidate>[];
  for (final r in await _fetchAll(client, names)) {
    final String? archive;
    try {
      archive = await _archiveIfPlugin(client, cache, r.package, platform);
    } on Exception catch (e) {
      stderr.writeln('skip ${r.package['name']}: $e');
      continue;
    }
    out.add(
      Candidate.fromJson(
        package: r.package,
        score: r.score,
        kind: classifyGlass(archive, platform: platform),
      ),
    );
  }
  final ranked = rank(out);
  return (
    ranked,
    platform == 'ios'
        ? renderGlassContext(ranked)
        : renderMacosGlassContext(ranked),
  );
}

Future<(List<Candidate>, String)> _expressive(
  http.Client client,
  Directory? cache,
) async {
  final names = await _candidateNames(client, 'android');
  final out = <Candidate>[];
  var officialOptIn = false;
  for (final r in await _fetchAll(client, names)) {
    final name = r.package['name'];
    final isOfficial = name == officialMaterial;
    if (!isOfficial && !isExpressiveRelated(r.package)) continue;
    final String? archive;
    try {
      archive = isOfficial
          ? await _archive(client, cache, r.package)
          : await _archiveIfPlugin(client, cache, r.package, 'android');
    } on Exception catch (e) {
      stderr.writeln('skip $name: $e');
      continue;
    }
    if (isOfficial) officialOptIn = styleVariantWired(archive!);
    out.add(
      Candidate.fromJson(
        package: r.package,
        score: r.score,
        kind: classifyExpressive(r.package, archiveText: archive),
      ),
    );
  }
  final ranked = rank(out);
  return (
    ranked,
    renderExpressiveContext(ranked, officialOptIn: officialOptIn),
  );
}

/// Fetches pub.dev data for [names], dropping failures and discontinued ones.
Future<List<({Map<String, dynamic> package, Map<String, dynamic> score})>>
_fetchAll(http.Client client, Iterable<String> names) async {
  final fetched = await Future.wait(
    names.map((n) async {
      try {
        return await fetchPackage(client, n);
      } on Exception catch (e) {
        stderr.writeln('skip $n: $e');
        return null;
      }
    }),
  );
  return [
    for (final r in fetched.nonNulls)
      if (r.package['isDiscontinued'] != true) r,
  ];
}

Future<String> _archive(
  http.Client client,
  Directory? cache,
  Map<String, dynamic> package,
) {
  stderr.writeln('scanning ${package['name']} ...');
  return fetchArchiveText(
    client,
    package['latest']['archive_url'] as String,
    cache: cache,
  );
}

Future<String?> _archiveIfPlugin(
  http.Client client,
  Directory? cache,
  Map<String, dynamic> package,
  String platform,
) async => isPluginFor(package, platform)
    ? await _archive(client, cache, package)
    : null;
