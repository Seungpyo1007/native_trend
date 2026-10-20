import 'package:http/http.dart' as http;
import 'package:native_trend/native_trend.dart';

/// Ranks iOS Liquid Glass packages from code instead of the CLI, then
/// classifies one package on its own.
Future<void> main() async {
  final client = http.Client();
  try {
    final api = PubApi(client, cache: defaultCacheDir());
    final result = await TrendFinder(api).find('ios');
    print(renderText(result.ranked.take(3).toList()));

    final r = await api.fetchPackage('cupertino_native_better');
    final source = isPluginFor(r.package, 'ios')
        ? await api.fetchSourceText(r.package)
        : null;
    final c = Candidate.fromJson(
      package: r.package,
      score: r.score,
      kind: classifyGlass(source),
    );
    print(renderText([c]));
  } finally {
    client.close();
  }
}
