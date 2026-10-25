import 'dart:convert';

import 'smtp_connection.dart';

/// The SMTP steps that the SMTP and sendmail transports share.
class SmtpProtocol {
  SmtpProtocol._();

  /// Says EHLO (or HELO when the server does not know EHLO) and keeps
  /// the extensions of the server.
  static Future<void> hello(SmtpConnection c, String localDomain) async {
    c.write('EHLO $localDomain\r\n');
    SmtpReply reply = await c.read();
    if (reply.code == 250) {
      c.extensions = reply.lines
          .skip(1)
          .map((String l) => l.trim().toUpperCase())
          .toList();
      return;
    }
    await c.command('HELO $localDomain', <int>[250]);
    c.extensions = <String>[];
  }

  /// MAIL FROM, RCPT TO for each recipient, then DATA with [mime].
  static Future<SmtpReply> sendMail(
    SmtpConnection c, {
    required String from,
    required List<String> recipients,
    required String mime,
  }) async {
    await c.command('MAIL FROM:<$from>', <int>[250]);
    for (String to in recipients) {
      await c.command('RCPT TO:<$to>', <int>[250, 251]);
    }
    await c.command('DATA', <int>[354]);
    c.writeBytes(utf8.encode(dotStuff(mime)));
    return c.expect(<int>[250], 'DATA');
  }

  /// [mime] for the DATA command: a line that starts with `.` gets one
  /// more `.`, and a line with only `.` ends it.
  static String dotStuff(String mime) {
    String text = mime.endsWith('\r\n') ? mime : '$mime\r\n';
    text = text.replaceAll('\r\n.', '\r\n..');
    if (text.startsWith('.')) text = '.$text';
    return '$text.\r\n';
  }
}
