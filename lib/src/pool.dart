/// Maps [items] through [f] with at most [concurrency] calls in flight,
/// keeping the input order in the result.
Future<List<R>> mapPool<T, R>(
  Iterable<T> items,
  int concurrency,
  Future<R> Function(T) f,
) async {
  final list = items.toList();
  final results = List<R?>.filled(list.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < list.length) {
      final i = next++;
      results[i] = await f(list[i]);
    }
  }

  await Future.wait([
    for (var w = 0; w < concurrency && w < list.length; w++) worker(),
  ]);
  return results.cast<R>();
}
