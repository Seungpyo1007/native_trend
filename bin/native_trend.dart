import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:native_trend/native_trend.dart';

const _usage = '''
Usage: native_trend find [options]

Finds Liquid Glass plugins on pub.dev that use real native iOS views,
prints them ranked, and writes an AI context file.
''';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand(
      'find',
      ArgParser()
        ..addOption('dir', defaultsTo: '.', help: 'Project root.')
        ..addOption('out', defaultsTo: '.ai/native_trend.md')
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

  final client = http.Client();
  final List<Candidate> ranked;
  try {
    ranked = rank(await _candidates(client));
  } finally {
    client.close();
  }
  stdout.writeln(renderText(ranked));

  final dir = cmd.option('dir')!;
  final rel = cmd.option('out')!;
  final out = File('$dir/$rel');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(renderContext(ranked));
  stdout.writeln('\nWrote ${out.path}');
  for (final name in cmd.multiOption('link')) {
    final target = File('$dir/$name');
    final text = target.existsSync() ? target.readAsStringSync() : '';
    if (text.contains(rel)) continue;
    final sep = text.isEmpty ? '' : (text.endsWith('\n') ? '\n' : '\n\n');
    target.writeAsStringSync(
      '$text${sep}Read `$rel` before adding or changing Liquid Glass UI.\n',
    );
    stdout.writeln('Linked from ${target.path}');
  }
}

Future<List<Candidate>> _candidates(http.Client client) async {
  final names = await search(client, glassQuery);
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

  final out = <Candidate>[];
  for (final r in fetched.nonNulls) {
    if (r.package['isDiscontinued'] == true) continue;
    String? archive;
    if (isIosPlugin(r.package)) {
      final name = r.package['name'];
      stderr.writeln('scanning $name ...');
      // ponytail: archives are 1-50 MB and fetched one at a time with no
      // cache; add a cache dir if repeat runs get slow.
      try {
        archive = await fetchArchiveText(
          client,
          r.package['latest']['archive_url'] as String,
        );
      } on Exception catch (e) {
        stderr.writeln('skip $name: $e');
        continue;
      }
    }
    out.add(
      Candidate.fromJson(
        package: r.package,
        score: r.score,
        kind: classify(archive),
      ),
    );
  }
  return out;
}
