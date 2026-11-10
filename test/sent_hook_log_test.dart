import 'dart:async';

import 'package:dox_core/dox_core.dart' show AppConfig, Dox, LoggerConfig;
import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

// Own file: it turns on the Dox logger, and other tests need it off.

/// a print that fails, so the Logger throws an Exception (not an Error)
void _brokenPrint(Zone self, ZoneDelegate parent, Zone zone, String line) {
  throw const FormatException('print is broken');
}

void _throwingHook(SentMessage sent) => throw StateError('hook failed');

Future<SentMessage> _send() {
  return Mail.send(
    Message(
      to: const <Address>[Address('ann@example.com')],
      subject: 'Hi',
      text: 'Hello',
    ),
  );
}

void main() {
  test('an onSent hook error is not thrown when the logger throws an '
      'Exception', () async {
    Dox().initialize(
      AppConfig(
        appKey: 'k' * 32,
        totalIsolate: 1,
        logger: LoggerConfig(enabled: true),
      ),
    );
    ArrayTransport main = ArrayTransport();
    Mail.configure(
      MailConfig(
        defaultMailer: 'main',
        from: const Address('app@example.com'),
        mailers: <String, Transport>{'main': main},
      ),
    );
    Mail.onSent(_throwingHook);
    addTearDown(Mail.clearHooks);

    SentMessage sent = await runZoned(
      _send,
      zoneSpecification: ZoneSpecification(print: _brokenPrint),
    );
    expect(main.sent.single.messageId, sent.messageId);
  });
}
