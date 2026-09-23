import 'package:http/http.dart' as http;
import 'package:native_trend/native_trend.dart';

/// Classifies one package from code instead of the CLI.
Future<void> main() async {
  final client = http.Client();
  try {
    final r = await fetchPackage(client, 'cupertino_native_better');
    final archive = isIosPlugin(r.package)
        ? await fetchArchiveText(
            client,
            r.package['latest']['archive_url'] as String,
          )
        : null;
    final c = Candidate.fromJson(
      package: r.package,
      score: r.score,
      kind: classify(archive),
    );
    print(renderText([c]));
  } finally {
    client.close();
  }
}
