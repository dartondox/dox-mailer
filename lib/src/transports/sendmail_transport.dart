import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../address.dart';
import '../mail_exception.dart';
import '../message.dart';
import '../mime/mime_builder.dart';
import '../smtp/smtp_connection.dart';
import '../smtp/smtp_protocol.dart';
import '../transport.dart';

/// How to talk to sendmail.
enum SendmailMode {
  /// `sendmail -bs`: speak SMTP on stdin and stdout
  smtp,

  /// `sendmail -t -i`: pipe the message in. sendmail reads the
  /// recipients from the To, Cc and Bcc headers, and removes Bcc.
  pipe,
}

/// Sends with the local `sendmail` program (Postfix, Exim, msmtp, ...).
/// ```
/// 'sendmail': SendmailTransport(),
/// ```
class SendmailTransport extends Transport {
  SendmailTransport({
    this.path = '/usr/sbin/sendmail',
    this.mode = SendmailMode.smtp,
    this.localDomain = 'localhost',
    this.timeout = const Duration(seconds: 30),
    MimeBuilder? mime,
  }) : mime = mime ?? MimeBuilder();

  /// the sendmail program
  final String path;

  final SendmailMode mode;

  /// the name of this machine, for EHLO in [SendmailMode.smtp]
  final String localDomain;

  /// how long sendmail can take
  final Duration timeout;

  final MimeBuilder mime;

  @override
  Future<SentMessage> send(Message message) async {
    MimeMessage raw = mime.build(
      message,
      includeBcc: mode == SendmailMode.pipe,
    );
    List<String> args = mode == SendmailMode.smtp
        ? <String>['-bs']
        : <String>['-t', '-i'];
    Process process;
    try {
      process = await Process.start(path, args);
    } catch (error) {
      throw MailException('sendmail: can not run $path: $error');
    }
    Future<String> errors = process.stderr
        .transform(utf8.decoder)
        .join()
        .catchError((Object _) => '');
    try {
      if (mode == SendmailMode.smtp) {
        await _smtp(process, message, raw);
      } else {
        unawaited(process.stdout.drain<void>());
        try {
          // sendmail wants the line ends of the system
          process.stdin.add(utf8.encode(raw.text.replaceAll('\r\n', '\n')));
          await process.stdin.close();
        } on IOException {
          // sendmail stopped early: its exit code tells why
        }
      }
      int code = await process.exitCode.timeout(timeout);
      if (code != 0) {
        throw MailException(
          'sendmail: exit code $code: ${(await errors).trim()}',
          statusCode: code,
        );
      }
    } on TimeoutException {
      process.kill();
      throw MailException('sendmail: no end in ${timeout.inSeconds} seconds');
    } on MailException {
      process.kill();
      rethrow;
    }
    return SentMessage(message, messageId: raw.messageId, raw: raw.text);
  }

  Future<void> _smtp(Process process, Message message, MimeMessage raw) async {
    SmtpConnection c = SmtpConnection(
      process.stdout,
      process.stdin,
      timeout: timeout,
    );
    try {
      await c.expect(<int>[220], 'greeting');
      await SmtpProtocol.hello(c, localDomain);
      await SmtpProtocol.sendMail(
        c,
        from: message.from!.email,
        recipients: message.recipients.map((Address a) => a.email).toList(),
        mime: raw.text,
      );
      await c.command('QUIT', <int>[221]);
    } finally {
      await c.close();
    }
  }
}
