import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:native_trend/native_trend.dart';

const _usage = '''
Usage: native_trend find [options]

Finds the pub.dev packages that best follow the platform's design trend,
prints them ranked, and writes an AI context file.
  ios:     Liquid Glass plugins that use real native iOS views
  android: Material 3 Expressive, official material_ui first
''';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand(
      'find',
      ArgParser()
        ..addOption('platform', allowed: ['ios', 'android'], defaultsTo: 'ios')
        ..addOption('dir', defaultsTo: '.', help: 'Project root.')
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

  final platform = cmd.option('platform')!;
  final client = http.Client();
  final (List<Candidate>, String) result;
  try {
    result = platform == 'ios'
        ? await _glass(client)
        : await _expressive(client);
  } finally {
    client.close();
  }
  final (ranked, context) = result;
  stdout.writeln(renderText(ranked));

  final dir = cmd.option('dir')!;
  final rel = cmd.option('out') ?? '.ai/native_trend_$platform.md';
  final out = File('$dir/$rel');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(context);
  stdout.writeln('\nWrote ${out.path}');
  final topic = platform == 'ios' ? 'Liquid Glass' : 'Material 3 Expressive';
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

Future<(List<Candidate>, String)> _glass(http.Client client) async {
  final out = <Candidate>[];
  for (final r in await _fetchAll(client, await search(client, glassQuery))) {
    final String? archive;
    try {
      archive = await _archiveIfPlugin(client, r.package, 'ios');
    } on Exception catch (e) {
      stderr.writeln('skip ${r.package['name']}: $e');
      continue;
    }
    out.add(
      Candidate.fromJson(
        package: r.package,
        score: r.score,
        kind: classifyGlass(archive),
      ),
    );
  }
  final ranked = rank(out);
  return (ranked, renderGlassContext(ranked));
}

Future<(List<Candidate>, String)> _expressive(http.Client client) async {
  final names = {
    officialMaterial,
    for (final q in expressiveQueries) ...await search(client, q),
  };
  final out = <Candidate>[];
  var officialOptIn = false;
  for (final r in await _fetchAll(client, names)) {
    final name = r.package['name'];
    final isOfficial = name == officialMaterial;
    if (!isOfficial && !isExpressiveRelated(r.package)) continue;
    final String? archive;
    try {
      archive = isOfficial
          ? await _archive(client, r.package)
          : await _archiveIfPlugin(client, r.package, 'android');
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

Future<String> _archive(http.Client client, Map<String, dynamic> package) {
  stderr.writeln('scanning ${package['name']} ...');
  // ponytail: archives are 1-50 MB and fetched one at a time with no cache;
  // add a cache dir if repeat runs get slow.
  return fetchArchiveText(client, package['latest']['archive_url'] as String);
}

Future<String?> _archiveIfPlugin(
  http.Client client,
  Map<String, dynamic> package,
  String platform,
) async =>
    isPluginFor(package, platform) ? await _archive(client, package) : null;
