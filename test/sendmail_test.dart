@TestOn('posix')
library;

import 'dart:io';

import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

/// A fake `sendmail` that writes its arguments and input to a log file.
/// With `-bs` it answers like an SMTP server.
const String _script = r'''
#!/bin/sh
log="$(dirname "$0")/log.txt"
echo "ARGS $*" > "$log"
if [ "$1" = "-bs" ]; then
  printf '220 fake ESMTP\r\n'
  while IFS= read -r line; do
    line=$(printf '%s' "$line" | tr -d '\r')
    echo "$line" >> "$log"
    case "$line" in
      EHLO*) printf '250-fake\r\n250 8BITMIME\r\n' ;;
      DATA)
        printf '354 go\r\n'
        while IFS= read -r data; do
          data=$(printf '%s' "$data" | tr -d '\r')
          echo "$data" >> "$log"
          [ "$data" = "." ] && break
        done
        printf '250 queued\r\n' ;;
      QUIT) printf '221 bye\r\n'; exit 0 ;;
      *) printf '250 ok\r\n' ;;
    esac
  done
else
  cat >> "$log"
fi
exit 0
''';

Message _message() => Message(
  from: const Address('app@example.com'),
  to: <Address>[const Address('ann@example.com')],
  bcc: <Address>[const Address('boss@example.com')],
  subject: 'Hi',
  text: 'Hello\n.\nbye',
);

void main() {
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dox_mailer_');
    path = '${dir.path}/sendmail';
    await File(path).writeAsString(_script.trimLeft());
    await Process.run('chmod', <String>['+x', path]);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  String log() => File('${dir.path}/log.txt').readAsStringSync();

  test('-t -i pipes the message with the Bcc header', () async {
    SendmailTransport sendmail = SendmailTransport(
      path: path,
      mode: SendmailMode.pipe,
    );
    SentMessage sent = await sendmail.send(_message());
    String text = log();
    expect(text, startsWith('ARGS -t -i\n'));
    expect(text, contains('To: ann@example.com\n'));
    expect(text, contains('Bcc: boss@example.com\n'));
    expect(text, contains('Message-ID: ${sent.messageId}\n'));
    expect(text, isNot(contains('\r')));
  });

  test('-bs speaks SMTP', () async {
    SendmailTransport sendmail = SendmailTransport(path: path);
    await sendmail.send(_message());
    String text = log();
    expect(text, startsWith('ARGS -bs\n'));
    expect(text, contains('EHLO localhost\n'));
    expect(text, contains('MAIL FROM:<app@example.com>\n'));
    expect(text, contains('RCPT TO:<ann@example.com>\n'));
    expect(text, contains('RCPT TO:<boss@example.com>\n'));
    expect(text, isNot(contains('Bcc:')));
    // the dot line of the body is stuffed
    expect(text, contains('Hello\n..\nbye\n.\nQUIT\n'));
  });

  test('a bad exit code is a MailException', () async {
    SendmailTransport sendmail = SendmailTransport(
      path: 'env',
      mode: SendmailMode.pipe,
    );
    // `env -t -i` fails: it has no -t option
    await expectLater(sendmail.send(_message()), throwsA(isA<MailException>()));
  });

  test('a missing program is a MailException', () async {
    SendmailTransport sendmail = SendmailTransport(path: '${dir.path}/nothing');
    await expectLater(sendmail.send(_message()), throwsA(isA<MailException>()));
  });
}
