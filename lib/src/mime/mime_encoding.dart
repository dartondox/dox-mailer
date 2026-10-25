import 'dart:convert';

/// Small helpers to write MIME text. Every line ends with CRLF.
class MimeEncoding {
  MimeEncoding._();

  static final RegExp _plainHeader = RegExp(r'^[\x20-\x7e]*$');

  /// [text] as it is when it is plain ASCII, else as RFC 2047 encoded
  /// words (`=?UTF-8?B?...?=`). Long text is split into more words,
  /// on a new folded line each.
  static String encodeWord(String text) {
    if (_plainHeader.hasMatch(text) && !text.contains('=?')) return text;
    List<String> words = <String>[];
    List<int> chunk = <int>[];
    for (int rune in text.runes) {
      List<int> bytes = utf8.encode(String.fromCharCode(rune));
      // 36 bytes are 48 base64 chars: a word is 60 chars, so the header
      // line stays under 78 chars
      if (chunk.length + bytes.length > 36) {
        words.add(_word(chunk));
        chunk = <int>[];
      }
      chunk.addAll(bytes);
    }
    if (chunk.isNotEmpty || words.isEmpty) words.add(_word(chunk));
    return words.join('\r\n ');
  }

  static String _word(List<int> bytes) => '=?UTF-8?B?${base64.encode(bytes)}?=';

  /// A header line, folded at spaces when it is longer than 78 chars.
  /// Encoded words are already folded.
  static String header(String name, String value) {
    String line = '$name: $value';
    if (line.length <= 78 || value.contains('\r\n')) return line;
    StringBuffer out = StringBuffer();
    int lineLength = 0;
    List<String> parts = line.split(' ');
    for (int i = 0; i < parts.length; i++) {
      String part = parts[i];
      if (i == 0) {
        out.write(part);
        lineLength = part.length;
      } else if (lineLength + 1 + part.length > 78) {
        out.write('\r\n $part');
        lineLength = part.length + 1;
      } else {
        out.write(' $part');
        lineLength += part.length + 1;
      }
    }
    return out.toString();
  }

  /// An address for a header: `"Lee, Ann" <ann@example.com>`. A name
  /// that is not plain ASCII is encoded.
  static String address(String email, String? name) {
    if (name == null || name.isEmpty) return email;
    String shown;
    if (!_plainHeader.hasMatch(name)) {
      shown = encodeWord(name);
    } else if (RegExp(r'[()<>\[\]:;@\\,."]').hasMatch(name)) {
      shown = '"${name.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
    } else {
      shown = name;
    }
    return '$shown <$email>';
  }

  /// Bytes as base64, 76 chars per line.
  static String base64Lines(List<int> bytes) {
    String text = base64.encode(bytes);
    StringBuffer out = StringBuffer();
    for (int i = 0; i < text.length; i += 76) {
      int end = i + 76 < text.length ? i + 76 : text.length;
      out.write(text.substring(i, end));
      out.write('\r\n');
    }
    return out.toString();
  }

  /// [text] as quoted-printable UTF-8 (RFC 2045). Lines are at most 76
  /// chars and end with CRLF.
  static String quotedPrintable(String text) {
    List<String> lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    StringBuffer out = StringBuffer();
    for (String line in lines) {
      List<int> bytes = utf8.encode(line);
      int length = 0;
      for (int i = 0; i < bytes.length; i++) {
        int b = bytes[i];
        bool last = i == bytes.length - 1;
        String token;
        if ((b >= 33 && b <= 126 && b != 61) ||
            ((b == 32 || b == 9) && !last)) {
          token = String.fromCharCode(b);
        } else {
          token = '=${b.toRadixString(16).toUpperCase().padLeft(2, '0')}';
        }
        // keep room for the "=" of a soft line break
        if (length + token.length > 75) {
          out.write('=\r\n');
          length = 0;
        }
        out.write(token);
        length += token.length;
      }
      out.write('\r\n');
    }
    return out.toString();
  }

  /// The `filename` (or `name`) parameter of a header. Plain names are
  /// quoted. Other names use RFC 2231 (`filename*=UTF-8''...`).
  static String fileParam(String key, String filename) {
    if (_plainHeader.hasMatch(filename) && !filename.contains('"')) {
      String safe = filename.replaceAll(r'\', r'\\');
      return '$key="$safe"';
    }
    StringBuffer out = StringBuffer();
    for (int b in utf8.encode(filename)) {
      bool keep =
          (b >= 0x30 && b <= 0x39) ||
          (b >= 0x41 && b <= 0x5a) ||
          (b >= 0x61 && b <= 0x7a) ||
          '!#\$&+-.^_`|~'.codeUnits.contains(b);
      out.write(
        keep
            ? String.fromCharCode(b)
            : '%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}',
      );
    }
    return "$key*=UTF-8''$out";
  }

  static const List<String> _days = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// A date for the `Date` header, in UTC: `Sun, 25 Oct 2026 10:00:00 +0000`.
  static String date(DateTime time) {
    DateTime t = time.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${_days[t.weekday - 1]}, ${t.day} ${_months[t.month - 1]} '
        '${t.year} ${two(t.hour)}:${two(t.minute)}:${two(t.second)} +0000';
  }
}
