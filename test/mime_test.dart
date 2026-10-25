import 'dart:convert';
import 'dart:math';

import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

MimeBuilder _builder() => MimeBuilder(
  clock: () => DateTime.utc(2026, 10, 25, 9, 5, 7),
  random: Random(1),
);

Message _message({
  String? text = 'Hello',
  String? html,
  List<Attachment> attachments = const <Attachment>[],
  String subject = 'Hi',
  Map<String, String> headers = const <String, String>{},
}) => Message(
  from: const Address('app@example.com', 'My App'),
  to: <Address>[const Address('ann@example.com', 'Ann')],
  cc: <Address>[const Address('bob@example.com')],
  bcc: <Address>[const Address('boss@example.com')],
  replyTo: <Address>[const Address('help@example.com')],
  subject: subject,
  text: text,
  html: html,
  attachments: attachments,
  headers: headers,
);

/// the headers of a part, up to the first empty line, unfolded
Map<String, String> _headers(String text) {
  String head = text.substring(0, text.indexOf('\r\n\r\n'));
  Map<String, String> out = <String, String>{};
  for (String line in head.replaceAll('\r\n ', ' ').split('\r\n')) {
    int colon = line.indexOf(': ');
    out[line.substring(0, colon)] = line.substring(colon + 2);
  }
  return out;
}

void main() {
  test('a text message', () {
    MimeMessage mime = _builder().build(_message());
    Map<String, String> h = _headers(mime.text);
    expect(h['Date'], 'Sun, 25 Oct 2026 09:05:07 +0000');
    expect(h['From'], 'My App <app@example.com>');
    expect(h['To'], 'Ann <ann@example.com>');
    expect(h['Cc'], 'bob@example.com');
    expect(h['Reply-To'], 'help@example.com');
    expect(h['Subject'], 'Hi');
    expect(h['MIME-Version'], '1.0');
    expect(h['Message-ID'], mime.messageId);
    expect(mime.messageId, matches(RegExp(r'^<[0-9a-f]{32}@example\.com>$')));
    expect(h['Content-Type'], 'text/plain; charset=utf-8');
    expect(h['Content-Transfer-Encoding'], 'quoted-printable');
    expect(h.containsKey('Bcc'), isFalse);
    expect(mime.text, endsWith('\r\n\r\nHello\r\n'));
  });

  test('every line ends with CRLF and is short', () {
    MimeMessage mime = _builder().build(
      _message(
        text: 'line one\nline two\r\n${'long ' * 40}\n',
        html: '<p>${'é' * 100}</p>',
        attachments: <Attachment>[
          Attachment(List<int>.filled(500, 7), 'a.bin'),
        ],
        subject: 'Grüße ${'and more words ' * 10}',
      ),
    );
    expect(mime.text.replaceAll('\r\n', ''), isNot(contains('\n')));
    expect(mime.text.replaceAll('\r\n', ''), isNot(contains('\r')));
    for (String line in mime.text.split('\r\n')) {
      expect(line.length, lessThanOrEqualTo(78), reason: line);
    }
    expect(() => ascii.encode(mime.text), returnsNormally);
  });

  test('includeBcc adds the Bcc header', () {
    MimeMessage mime = _builder().build(_message(), includeBcc: true);
    expect(_headers(mime.text)['Bcc'], 'boss@example.com');
  });

  test('RFC 2047 for headers that are not ASCII', () {
    MimeMessage mime = _builder().build(
      Message(
        from: const Address('app@example.com', 'Zoë'),
        to: <Address>[const Address('ann@example.com', 'Lee, Ann')],
        subject: 'Grüße',
        text: 'x',
      ),
    );
    Map<String, String> h = _headers(mime.text);
    expect(h['Subject'], '=?UTF-8?B?${base64.encode(utf8.encode('Grüße'))}?=');
    expect(
      h['From'],
      '=?UTF-8?B?${base64.encode(utf8.encode('Zoë'))}?= <app@example.com>',
    );
    expect(h['To'], '"Lee, Ann" <ann@example.com>');
  });

  test('a long subject is split into words on whole characters', () {
    String subject = '日本語のメール' * 10;
    String encoded = MimeEncoding.encodeWord(subject);
    List<String> words = encoded.split('\r\n ');
    expect(words.length, greaterThan(1));
    StringBuffer back = StringBuffer();
    for (String word in words) {
      expect(word.length, lessThanOrEqualTo(75));
      String b64 = word.substring(10, word.length - 2);
      back.write(utf8.decode(base64.decode(b64)));
    }
    expect(back.toString(), subject);
  });

  test('quoted-printable', () {
    expect(MimeEncoding.quotedPrintable('a=b é'), 'a=3Db =C3=A9\r\n');
    expect(MimeEncoding.quotedPrintable('end space '), 'end space=20\r\n');
    String long = MimeEncoding.quotedPrintable('x' * 200);
    List<String> lines = long.split('\r\n');
    expect(lines.first, '${'x' * 75}=');
    expect(lines.every((String l) => l.length <= 76), isTrue);
    expect(long.replaceAll('=\r\n', ''), '${'x' * 200}\r\n');
  });

  test('text and html are multipart/alternative', () {
    MimeMessage mime = _builder().build(_message(html: '<p>Hello</p>'));
    String type = _headers(mime.text)['Content-Type']!;
    expect(type, startsWith('multipart/alternative; boundary="=_dox_'));
    String boundary = RegExp('boundary="([^"]+)"').firstMatch(type)!.group(1)!;
    List<String> parts = mime.text.split('--$boundary');
    expect(parts, hasLength(4));
    expect(parts[1], contains('Content-Type: text/plain; charset=utf-8'));
    expect(parts[2], contains('Content-Type: text/html; charset=utf-8'));
    expect(parts[3], '--\r\n');
  });

  test('html only is a single part', () {
    MimeMessage mime = _builder().build(_message(text: null, html: '<b>x</b>'));
    expect(_headers(mime.text)['Content-Type'], 'text/html; charset=utf-8');
  });

  test('attachments make multipart/mixed, inline files multipart/related', () {
    MimeMessage mime = _builder().build(
      _message(
        html: '<img src="cid:logo">',
        attachments: <Attachment>[
          Attachment(utf8.encode('PDF'), 'invoice.pdf'),
          Attachment(<int>[1, 2, 3], 'logo.png', cid: 'logo'),
        ],
      ),
    );
    String text = mime.text;
    expect(_headers(text)['Content-Type'], startsWith('multipart/mixed;'));
    expect(text, contains('Content-Type: multipart/alternative;'));
    expect(text, contains('Content-Type: multipart/related;'));
    int related = text.indexOf('multipart/related');
    expect(text.indexOf('text/html'), greaterThan(related));
    expect(text.indexOf('Content-ID: <logo>'), greaterThan(related));
    expect(text, contains('Content-Type: application/pdf; name="invoice.pdf"'));
    expect(
      text,
      contains('Content-Disposition: attachment; filename="invoice.pdf"'),
    );
    expect(text, contains('Content-Disposition: inline; filename="logo.png"'));
    expect(text, contains('${base64.encode(utf8.encode('PDF'))}\r\n'));
    expect(text, contains('AQID\r\n'));
  });

  test('an inline file with no html is a normal attachment', () {
    MimeMessage mime = _builder().build(
      _message(
        attachments: <Attachment>[
          Attachment(<int>[1], 'a.png', cid: 'a'),
        ],
      ),
    );
    expect(mime.text, isNot(contains('multipart/related')));
    expect(mime.text, contains('multipart/mixed'));
  });

  test('a file name that is not ASCII uses RFC 2231', () {
    expect(
      MimeEncoding.fileParam('filename', 'résumé.pdf'),
      "filename*=UTF-8''r%C3%A9sum%C3%A9.pdf",
    );
    expect(MimeEncoding.fileParam('filename', 'a b.pdf'), 'filename="a b.pdf"');
  });

  test('custom headers are added and can set the Message-ID', () {
    MimeMessage mime = _builder().build(
      _message(
        headers: <String, String>{
          'X-Campaign': 'fall',
          'Message-ID': '<fixed@example.com>',
        },
      ),
    );
    Map<String, String> h = _headers(mime.text);
    expect(h['X-Campaign'], 'fall');
    expect(h['Message-ID'], '<fixed@example.com>');
    expect(mime.messageId, '<fixed@example.com>');
    expect('Message-ID'.allMatches(mime.text), hasLength(1));
  });

  test('attachment content types from the extension', () {
    expect(Attachment(<int>[], 'a.PDF').contentType, 'application/pdf');
    expect(Attachment(<int>[], 'a.jpg').contentType, 'image/jpeg');
    expect(
      Attachment(<int>[], 'a.xyz').contentType,
      'application/octet-stream',
    );
    expect(
      Attachment(<int>[], 'a', contentType: 'text/x').contentType,
      'text/x',
    );
  });

  test('Message.check stops header injection and bad addresses', () {
    expect(
      () => _message(subject: 'Hi\r\nBcc: evil@example.com').check(),
      throwsA(isA<MailException>()),
    );
    expect(
      () => _message(headers: <String, String>{'X-A': 'a\nb'}).check(),
      throwsA(isA<MailException>()),
    );
    expect(
      () => Message(
        from: const Address('app@example.com'),
        to: <Address>[const Address('not an email')],
        text: 'x',
      ).check(),
      throwsA(isA<MailException>()),
    );
    expect(() => _message().check(), returnsNormally);
  });

  test('Address.parse', () {
    expect(
      Address.parse('Ann Lee <ann@example.com>'),
      const Address('ann@example.com', 'Ann Lee'),
    );
    expect(
      Address.parse('"Lee, Ann" <ann@example.com>'),
      const Address('ann@example.com', 'Lee, Ann'),
    );
    expect(
      Address.parse(' ann@example.com '),
      const Address('ann@example.com'),
    );
    expect(const Address('a@b.c', 'Lee, Ann').toString(), '"Lee, Ann" <a@b.c>');
  });
}
