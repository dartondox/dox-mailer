@Tags(<String>['integration'])
@TestOn('posix')
library;

import 'dart:io';

import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'mailpit.dart';

/// sendmail with the sendmail of Mailpit. MAILPIT_BIN is the path of the
/// mailpit program. test/integration/mailpit_sendmail.sh runs
/// `mailpit sendmail` and sends to the plain Mailpit server.
void main() {
  String host = env('MAILPIT_SMTP_HOST') ?? 'localhost';
  Mailpit mailpit = Mailpit(
    Uri.parse(env('MAILPIT_API') ?? 'http://$host:8025'),
  );
  String path = File('test/integration/mailpit_sendmail.sh').absolute.path;

  group('sendmail with Mailpit', () {
    test('-t -i', () async {
      String id = newId();
      SendmailTransport sendmail = SendmailTransport(
        path: path,
        mode: SendmailMode.pipe,
      );
      await sendmail.send(sampleMessage(id));
      // -t puts the Bcc header in the message, and a real sendmail
      // removes it. The sendmail of Mailpit does not remove it, so the
      // Bcc header is not checked here.
      expectSample(await mailpit.read(id), id, bccHidden: false);
    });

    test('-bs', () async {
      String id = newId();
      SendmailTransport sendmail = SendmailTransport(path: path);
      await sendmail.send(sampleMessage(id));
      expectSample(await mailpit.read(id), id);
    });
  }, skip: skipUnless('MAILPIT_BIN', 'Mailpit and get the mailpit program'));
}
