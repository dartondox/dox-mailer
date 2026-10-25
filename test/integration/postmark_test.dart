@Tags(<String>['integration'])
library;

import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Postmark against the real API, with the public test token
/// `POSTMARK_API_TEST`. Postmark checks the message and gives a
/// MessageID, but sends nothing. So the test can not read the mail back.
void main() {
  group(
    'Postmark API',
    () {
      test('accepts the message with the test token', () async {
        PostmarkTransport postmark = PostmarkTransport(
          serverToken: env('POSTMARK_TOKEN') ?? 'POSTMARK_API_TEST',
        );
        try {
          SentMessage sent = await postmark.send(sampleMessage(newId()));
          // send throws a MailException when the status is not 2xx
          expect(sent.messageId, isNotNull);
          expect(sent.messageId, isNotEmpty);
        } finally {
          await postmark.close();
        }
      });
    },
    skip: skipUnless('POSTMARK_TOKEN', 'nothing (set it to POSTMARK_API_TEST)'),
  );
}
