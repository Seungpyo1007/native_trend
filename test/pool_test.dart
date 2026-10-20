import 'package:native_trend/native_trend.dart';
import 'package:test/test.dart';

void main() {
  test('mapPool bounds concurrency and keeps order', () async {
    var running = 0;
    var peak = 0;
    final out = await mapPool(List.generate(10, (i) => i), 4, (i) async {
      running++;
      if (running > peak) peak = running;
      await Future<void>.delayed(Duration(milliseconds: 10 - i));
      running--;
      return i * 2;
    });
    expect(out, List.generate(10, (i) => i * 2));
    expect(peak, 4);
  });

  test('mapPool handles empty input', () async {
    expect(await mapPool(<int>[], 4, (i) async => i), isEmpty);
  });
}
