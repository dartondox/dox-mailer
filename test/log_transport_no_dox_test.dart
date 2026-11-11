import 'dart:async';

import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

// Own file: Dox must not be set up here.

void main() {
  test('useLogger prints the mail when Dox is not set up', () async {
    List<String> lines = <String>[];
    await runZoned(
      () => LogTransport(useLogger: true).send(
        Message(
          from: const Address('app@example.com'),
          to: <Address>[const Address('ann@example.com')],
          subject: 'Hi',
          text: 'Hello Ann',
        ),
      ),
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          lines.add(line);
        },
      ),
    );
    expect(lines.single, contains('Hello Ann'));
  });
}
