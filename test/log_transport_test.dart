import 'dart:async';

import 'package:dox_core/dox_core.dart' show AppConfig, Dox, LoggerConfig;
import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

// Own file: it sets up Dox with the logger off.

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

  test('bothBodies with one body shows only that body', () async {
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

  test('useLogger writes through the Dox logger', () async {
    // the logger is off, so the mail goes nowhere. With `print` it shows.
    Dox().initialize(
      AppConfig(
        appKey: 'k' * 32,
        totalIsolate: 1,
        // ignore: avoid_redundant_argument_values
        logger: LoggerConfig(enabled: false),
      ),
    );
    List<String> logged = await _printed(
      () => LogTransport(useLogger: true).send(_both()),
    );
    expect(logged, isEmpty);
    List<String> printed = await _printed(() => LogTransport().send(_both()));
    expect(printed, hasLength(1));
  });
}
