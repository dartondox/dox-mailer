import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

/// The value of the env var [name], or null when it is not set or empty.
String? env(String name) {
  String? value = Platform.environment[name];
  return value == null || value.isEmpty ? null : value;
}

/// A skip message when the env var [name] is not set, else null.
String? skipUnless(String name, String what) => env(name) == null
    ? '$name is not set: start $what to run these tests, '
          'see the "Integration tests" part of the README'
    : null;

/// A short random id. Each test puts it in the subject, to find its own
/// message on a shared test server.
String newId() {
  Random random = Random();
  return List<String>.generate(
    10,
    (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[random.nextInt(36)],
  ).join();
}

/// the bytes of the attachment: every byte value, so a bad encoding shows
final List<int> fileBytes = List<int>.generate(256, (int i) => i);

// Postmark does not take every file type (eg. not .bin), so it is a .pdf
const String fileName = 'report.pdf';

/// A message with every part the tests check. The subject has the [id]
/// and non-ASCII text, to test RFC 2047.
Message sampleMessage(String id) {
  return Message(
    from: const Address('app@example.com', 'Dox App'),
    to: <Address>[const Address('ann@example.com', 'Ann Lee')],
    cc: <Address>[const Address('carl@example.com')],
    bcc: <Address>[const Address('boss@example.com')],
    subject: 'Test $id: héllo wörld ✓ 日本',
    text: 'Hello Ann.\nThis is the text part ✓',
    html: '<p>Hello <b>Ann</b>. This is the html part ✓</p>',
    attachments: <Attachment>[Attachment(fileBytes, fileName)],
  );
}

/// An email read back from a test server.
class ReadMail {
  ReadMail({
    required this.from,
    required this.to,
    required this.cc,
    required this.subject,
    required this.text,
    required this.html,
    required this.files,
    required this.headerNames,
    this.envelope,
  });

  /// the email of the From header
  final String from;
  final List<String> to;
  final List<String> cc;
  final String subject;
  final String text;
  final String html;

  /// file name and bytes of each attachment
  final Map<String, List<int>> files;

  /// every header name of the top part, in lower case
  final Set<String> headerNames;

  /// the envelope recipients, when the server tells them
  final List<String>? envelope;
}

/// Checks that [mail] has what [sampleMessage] sent. With [bccHidden],
/// no Bcc header may be in the mail. When the server tells the envelope
/// recipients, the Bcc address must be one of them.
void expectSample(ReadMail mail, String id, {bool bccHidden = true}) {
  Message sent = sampleMessage(id);
  expect(mail.from, sent.from!.email);
  expect(mail.to, <String>['ann@example.com']);
  expect(mail.cc, <String>['carl@example.com']);
  expect(mail.subject, sent.subject);
  expect(_lines(mail.text), _lines(sent.text!));
  expect(mail.html.trim(), sent.html);
  expect(mail.files.keys, <String>[fileName]);
  expect(mail.files[fileName], fileBytes);
  if (bccHidden) {
    expect(mail.headerNames, isNot(contains('bcc')));
  }
  if (mail.envelope != null) {
    expect(
      mail.envelope,
      containsAll(<String>[
        'ann@example.com',
        'carl@example.com',
        'boss@example.com',
      ]),
    );
  }
}

String _lines(String text) => text.replaceAll('\r\n', '\n').trim();

/// Reads a MIME message, as made by [MimeBuilder]: headers with RFC 2047
/// words, multipart bodies, quoted-printable and base64. It is small and
/// only for these tests.
ReadMail parseMime(String raw, {List<String>? envelope}) {
  _MimePart root = _MimePart.parse(raw.replaceAll('\r\n', '\n'));
  String text = '';
  String html = '';
  Map<String, List<int>> files = <String, List<int>>{};
  void walk(_MimePart part) {
    String type = part.type;
    if (type.startsWith('multipart/')) {
      part.children().forEach(walk);
    } else if (part.fileName != null) {
      files[part.fileName!] = part.bytes();
    } else if (type == 'text/plain') {
      text = utf8.decode(part.bytes());
    } else if (type == 'text/html') {
      html = utf8.decode(part.bytes());
    }
  }

  walk(root);
  List<String> emails(String? value) {
    if (value == null) return <String>[];
    return RegExp(r'[^\s<>,"]+@[^\s<>,"]+')
        .allMatches(value)
        .map((Match m) => m.group(0)!)
        .toList();
  }

  return ReadMail(
    from: emails(root.header('from')).first,
    to: emails(root.header('to')),
    cc: emails(root.header('cc')),
    subject: decodeWords(root.header('subject') ?? ''),
    text: text,
    html: html,
    files: files,
    headerNames: root.headers.keys.toSet(),
    envelope: envelope,
  );
}

/// Decodes RFC 2047 encoded words (B and Q).
String decodeWords(String value) {
  String joined = value.replaceAllMapped(
    RegExp(r'(\?=)\s+(=\?)'),
    (Match m) => '${m[1]}${m[2]}',
  );
  RegExp word = RegExp(r'=\?([^?]+)\?([bBqQ])\?([^?]*)\?=');
  // decode the bytes of all words together: a character can be split
  // over two words
  List<int> bytes = <int>[];
  StringBuffer out = StringBuffer();
  int last = 0;
  void flush() {
    if (bytes.isNotEmpty) out.write(utf8.decode(bytes));
    bytes = <int>[];
  }

  for (Match m in word.allMatches(joined)) {
    if (m.start > last) {
      flush();
      out.write(joined.substring(last, m.start));
    }
    String data = m[3]!;
    if (m[2]!.toUpperCase() == 'B') {
      bytes.addAll(base64.decode(data));
    } else {
      bytes.addAll(_quoted(data.replaceAll('_', ' ')));
    }
    last = m.end;
  }
  flush();
  out.write(joined.substring(last));
  return out.toString();
}

List<int> _quoted(String text) {
  List<int> out = <int>[];
  String body = text.replaceAll('=\n', '');
  for (int i = 0; i < body.length; i++) {
    if (body[i] == '=' && i + 2 < body.length) {
      int? value = int.tryParse(body.substring(i + 1, i + 3), radix: 16);
      if (value != null) {
        out.add(value);
        i += 2;
        continue;
      }
    }
    out.addAll(utf8.encode(body[i]));
  }
  return out;
}

class _MimePart {
  _MimePart(this.headers, this.body);

  factory _MimePart.parse(String text) {
    int end = text.indexOf('\n\n');
    String head = end < 0 ? text : text.substring(0, end);
    String body = end < 0 ? '' : text.substring(end + 2);
    Map<String, String> headers = <String, String>{};
    // unfold the lines, then split name and value
    for (String line in head.replaceAll(RegExp(r'\n[ \t]+'), ' ').split('\n')) {
      int colon = line.indexOf(':');
      if (colon <= 0) continue;
      headers[line.substring(0, colon).trim().toLowerCase()] = line
          .substring(colon + 1)
          .trim();
    }
    return _MimePart(headers, body);
  }

  final Map<String, String> headers;
  final String body;

  String? header(String name) => headers[name];

  String get type =>
      (header('content-type') ?? 'text/plain').split(';').first.trim();

  String? param(String headerName, String name) {
    Match? m = RegExp(
      '$name="?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(header(headerName) ?? '');
    return m?.group(1);
  }

  String? get fileName {
    String? name =
        param('content-disposition', 'filename') ??
        param('content-type', 'name');
    return name == null ? null : decodeWords(name);
  }

  List<_MimePart> children() {
    String boundary = param('content-type', 'boundary')!;
    List<_MimePart> parts = <_MimePart>[];
    List<String> chunks = body.split('--$boundary');
    // chunk 0 is the preamble; the last one starts with "--"
    for (String chunk in chunks.skip(1)) {
      if (chunk.startsWith('--')) break;
      parts.add(_MimePart.parse(chunk.replaceFirst(RegExp(r'^\n'), '')));
    }
    return parts;
  }

  List<int> bytes() {
    String encoding = (header('content-transfer-encoding') ?? '7bit')
        .toLowerCase();
    if (encoding == 'base64') {
      return base64.decode(body.replaceAll(RegExp(r'\s'), ''));
    }
    if (encoding == 'quoted-printable') {
      return _quoted(body.replaceAll(RegExp(r'\n$'), ''));
    }
    return utf8.encode(body);
  }
}

/// GETs [uri] and decodes the JSON.
Future<Object?> getJson(Uri uri) async {
  HttpClient client = HttpClient();
  try {
    HttpClientRequest request = await client.getUrl(uri);
    HttpClientResponse response = await request.close();
    String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw StateError('GET $uri: ${response.statusCode} $body');
    }
    return jsonDecode(body);
  } finally {
    client.close();
  }
}

/// GETs [uri] and gives the body bytes.
Future<List<int>> getBytes(Uri uri) async {
  HttpClient client = HttpClient();
  try {
    HttpClientRequest request = await client.getUrl(uri);
    HttpClientResponse response = await request.close();
    List<int> bytes = <int>[];
    await for (List<int> chunk in response) {
      bytes.addAll(chunk);
    }
    if (response.statusCode != 200) {
      throw StateError('GET $uri: ${response.statusCode}');
    }
    return bytes;
  } finally {
    client.close();
  }
}

/// Calls [read] until it gives a value, for up to 10 seconds.
Future<T> eventually<T>(Future<T?> Function() read, String what) async {
  DateTime end = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    T? value = await read();
    if (value != null) return value;
    if (DateTime.now().isAfter(end)) {
      throw StateError('timed out: $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}
