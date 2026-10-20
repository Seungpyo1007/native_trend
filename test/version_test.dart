import 'dart:convert';
import 'dart:io';

import 'package:native_trend/native_trend.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('packageVersion matches pubspec.yaml and plugin.json', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
    final plugin =
        jsonDecode(File('.claude-plugin/plugin.json').readAsStringSync())
            as Map;
    expect(packageVersion, pubspec['version']);
    expect(packageVersion, plugin['version']);
  });
}
