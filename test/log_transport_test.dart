import 'dart:async';
import 'dart:io';

import 'package:dox_core/dox_core.dart' show AppConfig, Dox, LoggerConfig;
import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

// Own file: it sets up Dox and turns the logger on and off.

Message _both() {
  return Message(
    from: const Address('app@example.com'),
    to: <Address>[const Address('ann@example.com')],
    subject: 'Hi',
    text: 'Hello Ann',
    html: '<p>Hello Ann</p>',
  );
}

void _setUpDox({required bool logger}) {
  Dox().initialize(
    AppConfig(
      appKey: 'k' * 32,
      totalIsolate: 1,
      logger: LoggerConfig(enabled: logger),
    ),
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

/// a stdout that keeps the text. Newer `dox_core` logs to stdout.
class _Stdout implements Stdout {
  final StringBuffer text = StringBuffer();

  @override
  void write(Object? object) => text.write(object);

  @override
  void writeln([Object? object = '']) => text.writeln(object);

  @override
  Future<dynamic> get done => Completer<dynamic>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
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

  test('output wins over useLogger', () async {
    List<String> lines = <String>[];
    await LogTransport(output: lines.add, useLogger: true).send(_both());
    expect(lines.single, contains('Hello Ann'));
  });

  test('useLogger with the logger off writes nothing', () async {
    _setUpDox(logger: false);
    List<String> logged = await _printed(
      () => LogTransport(useLogger: true).send(_both()),
    );
    expect(logged, isEmpty);
    List<String> printed = await _printed(() => LogTransport().send(_both()));
    expect(printed, hasLength(1));
  });

  test('useLogger with the logger on writes the mail to the log', () async {
    _setUpDox(logger: true);
    _Stdout out = _Stdout();
    // the released dox_core logs with `print`, newer ones write to stdout
    List<String> printed = await IOOverrides.runZoned(() {
      return _printed(() async {
        await LogTransport(useLogger: true).send(_both());
        // newer dox_core writes info lines a few ms later
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
    }, stdout: () => out);
    String logged = '${printed.join('\n')}${out.text}';
    expect(logged, contains('Hello Ann'));
    expect(logged, contains('Subject: Hi'));
  });
}
