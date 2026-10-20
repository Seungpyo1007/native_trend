import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One regular file in a tar archive.
typedef TarFile = ({String path, Uint8List bytes});

/// Reads the regular files of an uncompressed tar: ustar, with pax and GNU
/// long names. Throws [FormatException] on a truncated or corrupt archive.
Iterable<TarFile> readTar(List<int> tar) sync* {
  final data = tar is Uint8List ? tar : Uint8List.fromList(tar);
  var offset = 0;
  String? longName;
  while (offset + 512 <= data.length) {
    final header = Uint8List.sublistView(data, offset, offset + 512);
    if (header.every((b) => b == 0)) break;
    final size = _octal(header, 124, 12);
    final type = header[156];
    var name = _string(header, 0, 100);
    if (_string(header, 257, 5) == 'ustar') {
      final prefix = _string(header, 345, 155);
      if (prefix.isNotEmpty) name = '$prefix/$name';
    }
    final start = offset + 512;
    if (start + size > data.length) {
      throw FormatException('Truncated tar entry', name);
    }
    final body = Uint8List.sublistView(data, start, start + size);
    offset = start + (size + 511) ~/ 512 * 512;
    if (type == 0x78) {
      // pax extended header for the next entry.
      longName = _paxPath(body) ?? longName;
    } else if (type == 0x4c) {
      // GNU long name for the next entry.
      longName = _string(body, 0, body.length);
    } else {
      if (type == 0x30 || type == 0) {
        yield (path: longName ?? name, bytes: body);
      }
      longName = null;
    }
  }
}

String _string(Uint8List bytes, int start, int length) {
  var end = start;
  while (end < start + length && bytes[end] != 0) {
    end++;
  }
  return utf8.decode(bytes.sublist(start, end), allowMalformed: true);
}

int _octal(Uint8List bytes, int start, int length) {
  final text = _string(bytes, start, length).trim();
  if (text.isEmpty) return 0;
  final value = int.tryParse(text, radix: 8);
  if (value == null) throw FormatException('Bad tar size', text);
  return value;
}

String? _paxPath(Uint8List body) {
  // Records are "<length> <key>=<value>\n".
  final text = utf8.decode(body, allowMalformed: true);
  for (final record in text.split('\n')) {
    final space = record.indexOf(' ');
    if (space < 0) continue;
    final entry = record.substring(space + 1);
    if (entry.startsWith('path=')) return entry.substring(5);
  }
  return null;
}

/// Folders that hold a package's own code.
const sourceDirs = ['lib/', 'ios/', 'macos/', 'darwin/', 'android/'];

/// Extensions of source files worth scanning.
const sourceExtensions = ['.dart', '.swift', '.m', '.mm', '.h', '.kt', '.java'];

/// True for a source file under [sourceDirs]. README, CHANGELOG, `example/`,
/// and `test/` don't count: mentioning a class there proves nothing.
bool isSourcePath(String path) {
  final p = path.startsWith('./') ? path.substring(2) : path;
  return sourceDirs.any(p.startsWith) && sourceExtensions.any(p.endsWith);
}

/// The source files in a gzipped package archive, comments removed and
/// joined into one string for substring search.
String packageSourceText(List<int> archiveGz) {
  final b = StringBuffer();
  for (final f in readTar(gzip.decode(archiveGz))) {
    if (!isSourcePath(f.path)) continue;
    b
      ..writeln(stripComments(utf8.decode(f.bytes, allowMalformed: true)))
      ..writeln();
  }
  return b.toString();
}

/// Removes `//` and (nested) `/* */` comments from Dart, Swift, Kotlin,
/// Java, and Objective-C source, leaving string literals alone.
///
/// Good enough for marker search, not a lexer: a single-line string ends at
/// the line break, and raw strings are read as ordinary ones.
String stripComments(String source) {
  final out = StringBuffer();
  final n = source.length;
  var i = 0;
  String? quote;
  while (i < n) {
    final c = source.codeUnitAt(i);
    if (quote != null) {
      if (source.startsWith(quote, i)) {
        out.write(quote);
        i += quote.length;
        quote = null;
      } else if (c == 0x5c && i + 1 < n) {
        // Backslash escape.
        out.write(source.substring(i, i + 2));
        i += 2;
      } else {
        if (c == 0x0a && quote.length == 1) quote = null;
        out.writeCharCode(c);
        i++;
      }
      continue;
    }
    if (source.startsWith('//', i)) {
      final nl = source.indexOf('\n', i);
      i = nl < 0 ? n : nl;
      continue;
    }
    if (source.startsWith('/*', i)) {
      var depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (source.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (source.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      out.write(' ');
      continue;
    }
    if (c == 0x22 || c == 0x27) {
      final triple = String.fromCharCodes([c, c, c]);
      quote = source.startsWith(triple, i) ? triple : String.fromCharCode(c);
      out.write(quote);
      i += quote.length;
      continue;
    }
    out.writeCharCode(c);
    i++;
  }
  return out.toString();
}
