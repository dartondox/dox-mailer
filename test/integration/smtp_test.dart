@Tags(<String>['integration'])
library;

import 'dart:async';
import 'dart:io';

import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'mailpit.dart';

/// SMTP against Mailpit. Three Mailpit servers run:
///
/// - plain: no TLS, no login (smtp 1025, api 8025)
/// - starttls: STARTTLS required, login user:secret (smtp 1026, api 8026)
/// - tls: TLS from the start, login user:secret (smtp 1027, api 8027)
///
/// Both TLS servers use a self-signed certificate.
void main() {
  String host = env('MAILPIT_SMTP_HOST') ?? 'localhost';
  int port(String name, int value) => int.parse(env(name) ?? '$value');
  Mailpit api(String name, int value) =>
      Mailpit(Uri.parse(env(name) ?? 'http://$host:$value'));

  int plainPort = port('MAILPIT_SMTP_PORT', 1025);
  int starttlsPort = port('MAILPIT_STARTTLS_PORT', 1026);
  int tlsPort = port('MAILPIT_TLS_PORT', 1027);
  Mailpit plainApi = api('MAILPIT_API', 8025);
  Mailpit starttlsApi = api('MAILPIT_STARTTLS_API', 8026);
  Mailpit tlsApi = api('MAILPIT_TLS_API', 8027);

  Future<void> sendWith(SmtpTransport smtp, Mailpit mailpit) async {
    String id = newId();
    try {
      SentMessage sent = await smtp.send(sampleMessage(id));
      expect(sent.messageId, isNotNull);
    } finally {
      await smtp.close();
    }
    expectSample(await mailpit.read(id), id);
  }

  group('SMTP with Mailpit', () {
    test('no TLS, no login', () async {
      await sendWith(
        SmtpTransport(
          host: host,
          port: plainPort,
          encryption: SmtpEncryption.none,
        ),
        plainApi,
      );
    });

    test('STARTTLS with AUTH PLAIN', () async {
      await sendWith(
        SmtpTransport(
          host: host,
          port: starttlsPort,
          allowInsecure: true,
          username: 'user',
          password: 'secret',
          auth: SmtpAuth.plain,
        ),
        starttlsApi,
      );
    });

    test('STARTTLS with AUTH LOGIN', () async {
      await sendWith(
        SmtpTransport(
          host: host,
          port: starttlsPort,
          allowInsecure: true,
          username: 'user',
          password: 'secret',
          auth: SmtpAuth.login,
        ),
        starttlsApi,
      );
    });

    test('STARTTLS picks a login method from EHLO', () async {
      await sendWith(
        SmtpTransport(
          host: host,
          port: starttlsPort,
          allowInsecure: true,
          username: 'user',
          password: 'secret',
        ),
        starttlsApi,
      );
    });

    test('implicit TLS with AUTH PLAIN', () async {
      await sendWith(
        SmtpTransport(
          host: host,
          port: tlsPort,
          encryption: SmtpEncryption.tls,
          allowInsecure: true,
          username: 'user',
          password: 'secret',
          auth: SmtpAuth.plain,
        ),
        tlsApi,
      );
    });

    test('implicit TLS with AUTH LOGIN', () async {
      await sendWith(
        SmtpTransport(
          host: host,
          port: tlsPort,
          encryption: SmtpEncryption.tls,
          allowInsecure: true,
          username: 'user',
          password: 'secret',
          auth: SmtpAuth.login,
        ),
        tlsApi,
      );
    });

    test('a wrong password fails', () async {
      SmtpTransport smtp = SmtpTransport(
        host: host,
        port: tlsPort,
        encryption: SmtpEncryption.tls,
        allowInsecure: true,
        username: 'user',
        password: 'wrong',
      );
      await expectLater(
        smtp.send(sampleMessage(newId())),
        throwsA(isA<MailException>()),
      );
      await smtp.close();
    });

    test('the self-signed certificate fails without allowInsecure', () async {
      SmtpTransport smtp = SmtpTransport(
        host: host,
        port: tlsPort,
        encryption: SmtpEncryption.tls,
        username: 'user',
        password: 'secret',
      );
      await expectLater(
        smtp.send(sampleMessage(newId())),
        throwsA(isA<MailException>()),
      );
      await smtp.close();
    });

    test('keepAlive sends 3 messages on one connection', () async {
      // a small TCP proxy in front of Mailpit counts the connections
      ServerSocket proxy = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      int connections = 0;
      proxy.listen((Socket client) async {
        connections++;
        Socket server = await Socket.connect(host, plainPort);
        unawaited(client.cast<List<int>>().pipe(server).catchError((_) {}));
        unawaited(server.cast<List<int>>().pipe(client).catchError((_) {}));
      });
      SmtpTransport smtp = SmtpTransport(
        host: InternetAddress.loopbackIPv4.address,
        port: proxy.port,
        encryption: SmtpEncryption.none,
        keepAlive: true,
      );
      List<String> ids = <String>[newId(), newId(), newId()];
      try {
        for (String id in ids) {
          await smtp.send(sampleMessage(id));
        }
      } finally {
        await smtp.close();
        await proxy.close();
      }
      expect(connections, 1);
      for (String id in ids) {
        expectSample(await plainApi.read(id), id);
      }
    });
  }, skip: skipUnless('MAILPIT_SMTP_HOST', 'Mailpit'));
}
