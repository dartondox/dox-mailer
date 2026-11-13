import 'dart:async';

import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

Message _both() {
  return Message(
    from: const Address('app@example.com'),
    to: <Address>[const Address('ann@example.com')],
    subject: 'Hi',
    text: 'Hello Ann',
    html: '<p>Hello Ann</p>',
  );
}

/// runs [body] and returns what it printed
Future<List<String>> _printed(Future<void> Function() body) async {
  List<String> lines = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        lines.add(line);
      },
    ),
  );
  return lines;
}

void main() {
  test('by default only the text body is shown', () async {
    List<String> lines = await _printed(() => LogTransport().send(_both()));
    expect(
      lines.single,
      '--- mail ---\n'
      'From: app@example.com\n'
      'To: ann@example.com\n'
      'Subject: Hi\n'
      '\n'
      'Hello Ann\n'
      '--- end ---',
    );
  });

  test('the default output with cc, bcc, headers and a file', () async {
    Message message = Message(
      from: const Address('app@example.com', 'App'),
      to: <Address>[const Address('ann@example.com')],
      cc: <Address>[const Address('bob@example.com')],
      bcc: <Address>[const Address('cat@example.com')],
      replyTo: <Address>[const Address('help@example.com')],
      subject: 'Invoice',
      headers: <String, String>{'X-Campaign': 'may'},
      attachments: <Attachment>[
        Attachment(<int>[1, 2, 3], 'a.pdf', contentType: 'application/pdf'),
      ],
      html: '<p>Hi</p>',
    );
    List<String> lines = await _printed(() => LogTransport().send(message));
    expect(
      lines.single,
      '--- mail ---\n'
      'From: App <app@example.com>\n'
      'To: ann@example.com\n'
      'Cc: bob@example.com\n'
      'Bcc: cat@example.com\n'
      'Reply-To: help@example.com\n'
      'Subject: Invoice\n'
      'X-Campaign: may\n'
      'Attachment: a.pdf (application/pdf, 3 bytes)\n'
      '\n'
      '<p>Hi</p>\n'
      '--- end ---',
    );
  });

  test('bothBodies shows the text and the HTML body', () async {
    List<String> lines = <String>[];
    await LogTransport(output: lines.add, bothBodies: true).send(_both());
    expect(
      lines.single,
      endsWith(
        'Subject: Hi\n'
        '\n'
        '--- text ---\n'
        'Hello Ann\n'
        '--- html ---\n'
        '<p>Hello Ann</p>\n'
        '--- end ---',
      ),
    );
  });

  test('bothBodies with only HTML shows only that body', () async {
    List<String> lines = <String>[];
    Message html = Message(
      from: const Address('app@example.com'),
      to: <Address>[const Address('ann@example.com')],
      html: '<p>Hi</p>',
    );
    await LogTransport(output: lines.add, bothBodies: true).send(html);
    expect(lines.single, endsWith('\n<p>Hi</p>\n--- end ---'));
    expect(lines.single, isNot(contains('--- html ---')));
  });

  test('bothBodies with only text shows only that body', () async {
    List<String> lines = <String>[];
    Message text = Message(
      from: const Address('app@example.com'),
      to: <Address>[const Address('ann@example.com')],
      text: 'Hi',
    );
    await LogTransport(output: lines.add, bothBodies: true).send(text);
    expect(lines.single, endsWith('\nHi\n--- end ---'));
    expect(lines.single, isNot(contains('--- text ---')));
  });
}
