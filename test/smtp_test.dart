import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

import 'fake_smtp_server.dart';

Message _message({String text = 'Hello Ann'}) => Message(
  from: const Address('app@example.com', 'App'),
  to: <Address>[const Address('ann@example.com')],
  cc: <Address>[const Address('bob@example.com')],
  bcc: <Address>[const Address('boss@example.com')],
  subject: 'Hi',
  text: text,
);

void main() {
  late FakeSmtpServer server;

  tearDown(() async {
    await server.close();
  });

  test('sends with no TLS and no login', () async {
    server = await FakeSmtpServer.start();
    SmtpTransport smtp = SmtpTransport(
      host: '127.0.0.1',
      port: server.port,
      encryption: SmtpEncryption.none,
      localDomain: 'app.test',
    );
    SentMessage sent = await smtp.send(_message());

    expect(server.commands.first, 'EHLO app.test');
    expect(server.commands, isNot(contains(startsWith('AUTH'))));
    expect(server.commands.last, 'QUIT');
    ReceivedMail mail = server.mails.single;
    expect(mail.from, 'app@example.com');
    expect(mail.recipients, <String>[
      'ann@example.com',
      'bob@example.com',
      'boss@example.com',
    ]);
    expect(mail.data, contains('Subject: Hi\r\n'));
    expect(mail.data, isNot(contains('boss@example.com')));
    expect(mail.data, contains('Message-ID: ${sent.messageId}\r\n'));
    expect(sent.raw, mail.data);
  });

  test('dot-stuffs lines that start with a dot', () async {
    server = await FakeSmtpServer.start();
    SmtpTransport smtp = SmtpTransport(
      host: '127.0.0.1',
      port: server.port,
      encryption: SmtpEncryption.none,
    );
    await smtp.send(_message(text: 'a\n.\n.b'));
    expect(server.mails.single.data, contains('a\r\n.\r\n.b\r\n'));
  });

  test('STARTTLS with a self-signed certificate and AUTH PLAIN', () async {
    server = await FakeSmtpServer.start(startTls: true);
    SmtpTransport smtp = SmtpTransport(
      host: '127.0.0.1',
      port: server.port,
      username: 'ann',
      password: 'secret',
      allowInsecure: true,
    );
    await smtp.send(_message());
    expect(server.commands, <Matcher>[
      equals('EHLO localhost'),
      equals('STARTTLS'),
      equals('EHLO localhost'),
      startsWith('AUTH PLAIN '),
      equals('MAIL FROM:<app@example.com>'),
      equals('RCPT TO:<ann@example.com>'),
      equals('RCPT TO:<bob@example.com>'),
      equals('RCPT TO:<boss@example.com>'),
      equals('DATA'),
      equals('QUIT'),
    ]);
    expect(server.mails, hasLength(1));
  });

  test('STARTTLS rejects a self-signed certificate by default', () async {
    server = await FakeSmtpServer.start(startTls: true);
    SmtpTransport smtp = SmtpTransport(host: '127.0.0.1', port: server.port);
    await expectLater(
      smtp.send(_message()),
      throwsA(
        isA<MailException>().having(
          (MailException e) => e.message,
          'message',
          contains('TLS failed'),
        ),
      ),
    );
    expect(server.mails, isEmpty);
  });

  test('STARTTLS fails when the server does not offer it', () async {
    server = await FakeSmtpServer.start();
    SmtpTransport smtp = SmtpTransport(host: '127.0.0.1', port: server.port);
    await expectLater(
      smtp.send(_message()),
      throwsA(
        isA<MailException>().having(
          (MailException e) => e.message,
          'message',
          contains('STARTTLS'),
        ),
      ),
    );
  });

  test('implicit TLS and AUTH LOGIN', () async {
    server = await FakeSmtpServer.start(implicitTls: true);
    SmtpTransport smtp = SmtpTransport(
      host: '127.0.0.1',
      port: server.port,
      encryption: SmtpEncryption.tls,
      allowInsecure: true,
      username: 'ann',
      password: 'secret',
      auth: SmtpAuth.login,
    );
    await smtp.send(_message());
    expect(server.commands, contains('AUTH LOGIN'));
    expect(server.mails, hasLength(1));
  });

  test('picks LOGIN when the server has no PLAIN', () async {
    server = await FakeSmtpServer.start(authMethods: 'LOGIN');
    SmtpTransport smtp = SmtpTransport(
      host: '127.0.0.1',
      port: server.port,
      encryption: SmtpEncryption.none,
      username: 'ann',
      password: 'secret',
    );
    await smtp.send(_message());
    expect(server.commands, contains('AUTH LOGIN'));
  });

  test('AUTH XOAUTH2 with a token', () async {
    server = await FakeSmtpServer.start(
      users: <String, String>{'ann@example.com': 'tok3n'},
    );
    SmtpTransport smtp = SmtpTransport(
      host: '127.0.0.1',
      port: server.port,
      encryption: SmtpEncryption.none,
      username: 'ann@example.com',
      password: 'tok3n',
      auth: SmtpAuth.xoauth2,
    );
    await smtp.send(_message());
    expect(server.mails, hasLength(1));
  });

  test('a bad XOAUTH2 token throws', () async {
    server = await FakeSmtpServer.start();
    SmtpTransport smtp = SmtpTransport(
      host: '127.0.0.1',
      port: server.port,
      encryption: SmtpEncryption.none,
      username: 'ann',
      password: 'old-token',
      auth: SmtpAuth.xoauth2,
    );
    await expectLater(
      smtp.send(_message()),
      throwsA(
        isA<MailException>().having(
          (MailException e) => e.statusCode,
          'statusCode',
          535,
        ),
      ),
    );
  });

  test('a wrong password throws and does not show the password', () async {
    server = await FakeSmtpServer.start();
    SmtpTransport smtp = SmtpTransport(
      host: '127.0.0.1',
      port: server.port,
      encryption: SmtpEncryption.none,
      username: 'ann',
      password: 'wrong',
    );
    Object? error;
    try {
      await smtp.send(_message());
    } catch (e) {
      error = e;
    }
    expect(error, isA<MailException>());
    expect(error.toString(), contains('AUTH PLAIN failed'));
    expect(error.toString(), isNot(contains('d3Jvbmc')));
  });

  test('a rejected recipient throws with the code', () async {
    server = await FakeSmtpServer.start();
    server.failOn['RCPT TO:<BOB'] = '550 no such user';
    SmtpTransport smtp = SmtpTransport(
      host: '127.0.0.1',
      port: server.port,
      encryption: SmtpEncryption.none,
    );
    await expectLater(
      smtp.send(_message()),
      throwsA(
        isA<MailException>().having(
          (MailException e) => e.statusCode,
          'statusCode',
          550,
        ),
      ),
    );
  });

  test('keepAlive sends many messages on one connection', () async {
    server = await FakeSmtpServer.start();
    SmtpTransport smtp = SmtpTransport(
      host: '127.0.0.1',
      port: server.port,
      encryption: SmtpEncryption.none,
      keepAlive: true,
    );
    await Future.wait(<Future<SentMessage>>[
      smtp.send(_message()),
      smtp.send(_message()),
      smtp.send(_message()),
    ]);
    expect(server.connections, 1);
    expect(server.mails, hasLength(3));
    expect(server.commands.where((String c) => c == 'RSET'), hasLength(2));
    await smtp.close();
    expect(server.commands.last, 'QUIT');
  });

  test('a connect error is a MailException', () async {
    server = await FakeSmtpServer.start();
    int port = server.port;
    await server.close();
    SmtpTransport smtp = SmtpTransport(
      host: '127.0.0.1',
      port: port,
      encryption: SmtpEncryption.none,
      timeout: const Duration(seconds: 2),
    );
    await expectLater(smtp.send(_message()), throwsA(isA<MailException>()));
  });
}
