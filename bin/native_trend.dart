import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:native_trend/native_trend.dart';

const _usage = '''
Usage: native_trend find [options]
       native_trend audit [options]
       native_trend cache clean|path

find: finds the pub.dev packages that best follow the platform's design
trend, prints them ranked, and writes an AI context file per platform.
  ios:     Liquid Glass plugins that use real native iOS views
  macos:   Liquid Glass plugins that use real native AppKit views
  android: Material 3 Expressive, official material_ui first
Without --platform, uses the platform folders in --dir (ios if none).

audit: checks the project's dependencies against the same rankings and
exits with 1 when one should be replaced.

cache: deletes or prints the package archive cache.

Exit codes: 0 ok, 1 audit found a dependency to replace, 64 bad usage,
66 no pubspec.yaml, 69 pub.dev unreachable.
''';

const _platformHelp = 'ios, android, macos, or all. Repeatable or comma list.';
const _cacheHelp =
    'Keep downloaded package archives in the user cache directory.';

ArgParser _common(ArgParser p) => p
  ..addMultiOption(
    'platform',
    allowed: [...trendPlatforms, 'all'],
    help: _platformHelp,
  )
  ..addOption('dir', defaultsTo: '.', help: 'Project root.')
  ..addFlag('cache', defaultsTo: true, help: _cacheHelp)
  ..addOption('pages', defaultsTo: '3', help: 'pub.dev search pages per query.')
  ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addFlag('version', negatable: false, help: 'Print the version.')
    ..addCommand(
      'find',
      _common(ArgParser())
        ..addOption(
          'out',
          help:
              'Output path, with one platform only. '
              'Default: .ai/native_trend_<platform>.md',
        )
        ..addMultiOption(
          'link',
          help:
              'Add a pointer to the output in these files, '
              'e.g. AGENTS.md or CLAUDE.md.',
        ),
    )
    ..addCommand('audit', _common(ArgParser()))
    ..addCommand(
      'cache',
      ArgParser()
        ..addCommand('clean')
        ..addCommand('path'),
    );

  final ArgResults opts;
  try {
    opts = parser.parse(args);
  } on FormatException catch (e) {
    _usageError(e.message, parser);
  }
  final cmd = opts.command;
  if (opts.flag('version')) {
    stdout.writeln(packageVersion);
    return;
  }
  if (opts.flag('help') || cmd == null) {
    stdout.writeln('$_usage\n${parser.usage}');
    return;
  }
  if (cmd.name == 'cache') return _cache(cmd);

  final pages = int.tryParse(cmd.option('pages')!);
  if (pages == null || pages < 1) {
    _usageError('--pages must be a positive number.', parser);
  }
  final dir = cmd.option('dir')!;
  final project = Project.read(Directory(dir));
  if (cmd.name == 'audit' && !project.hasPubspec) {
    stderr.writeln('No pubspec.yaml in $dir');
    exit(66);
  }
  final asked = cmd.multiOption('platform');
  final platforms = asked.contains('all')
      ? trendPlatforms
      : asked.isNotEmpty
      ? [
          for (final p in trendPlatforms)
            if (asked.contains(p)) p,
        ]
      : project.targets.isNotEmpty
      ? project.targets
      : cmd.name == 'audit'
      ? trendPlatforms
      : ['ios'];
  if (cmd.name == 'find' && cmd.option('out') != null && platforms.length > 1) {
    _usageError('--out needs a single --platform.', parser);
  }

  final client = http.Client();
  final finder = TrendFinder(
    PubApi(client, cache: cmd.flag('cache') ? defaultCacheDir() : null),
    project: project,
    pages: pages,
    log: stderr.writeln,
  );
  try {
    if (cmd.name == 'find') {
      await _find(finder, cmd, dir, platforms);
    } else if (!await _audit(finder, cmd, project, platforms)) {
      exitCode = 1;
    }
  } on Exception catch (e) {
    if (!isNetworkError(e)) rethrow;
    stderr.writeln(
      'native_trend: could not reach pub.dev ($e).\n'
      'Check your connection and try again.',
    );
    exitCode = 69;
  } finally {
    client.close();
  }
}

Never _usageError(String message, ArgParser parser) {
  stderr.writeln('$message\n\n$_usage\n${parser.usage}');
  exit(64);
}

Map<String, Object?> _envelope(Map<String, Object?> body) => {
  'schema': 1,
  'tool': 'native_trend',
  'version': packageVersion,
  'checkedAt': DateTime.now().toUtc().toIso8601String(),
  ...body,
};

Future<void> _find(
  TrendFinder finder,
  ArgResults cmd,
  String dir,
  List<String> platforms,
) async {
  final json = cmd.flag('json');
  // With --json, stdout carries only the JSON.
  final info = json ? stderr : stdout;
  final results = <Map<String, Object?>>[];
  for (final platform in platforms) {
    final result = await finder.find(platform);
    if (!json) {
      if (platforms.length > 1) stdout.writeln('\n$platform');
      stdout.writeln(renderText(result.ranked));
    }
    final rel = cmd.option('out') ?? '.ai/native_trend_$platform.md';
    final out = writeContext(dir, rel, result.context);
    info.writeln('${json ? '' : '\n'}Wrote ${out.path}');
    final topic = platform == 'android'
        ? 'Material 3 Expressive'
        : 'Liquid Glass';
    for (final name in cmd.multiOption('link')) {
      final linked = linkContext(dir, name, rel, topic);
      if (linked != null) info.writeln('Linked from ${linked.path}');
    }
    results.add({...result.toJson(), 'output': rel});
  }
  if (json) {
    stdout.writeln(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(_envelope({'results': results})),
    );
  }
}

/// Returns true when every matching dependency is worth keeping.
Future<bool> _audit(
  TrendFinder finder,
  ArgResults cmd,
  Project project,
  List<String> platforms,
) async {
  final deps = project.dependencies;
  final depData = await finder.fetchDeps(deps);
  final results = [
    for (final platform in platforms)
      await finder.audit(platform, deps, depData),
  ];
  final clean = results.every((r) => r.clean);
  if (cmd.flag('json')) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(
        _envelope({
          'clean': clean,
          'results': [for (final r in results) r.toJson()],
        }),
      ),
    );
  } else {
    for (final r in results) {
      stdout.writeln(renderAudit(r.platform, r.findings));
    }
  }
  return clean;
}

void _cache(ArgResults cmd) {
  final dir = defaultCacheDir();
  if (dir == null) {
    stderr.writeln(
      'No cache directory: set HOME (or LOCALAPPDATA on Windows).',
    );
    exit(78);
  }
  switch (cmd.command?.name) {
    case 'path':
      stdout.writeln(dir.path);
    case 'clean':
      final bytes = cleanCache(dir);
      stdout.writeln(
        'Removed ${(bytes / 1e6).toStringAsFixed(1)} MB from ${dir.path}',
      );
    default:
      stderr.writeln('Usage: native_trend cache clean|path');
      exit(64);
  }
}
