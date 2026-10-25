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

/// How the SMTP connection is secured.
enum SmtpEncryption {
  /// no TLS. Only for a local server, eg. Mailpit.
  none,

  /// connect with plain text, then switch to TLS with STARTTLS (port 587)
  starttls,

  /// TLS from the start (port 465)
  tls,
}

/// How to log in to the SMTP server.
enum SmtpAuth {
  plain,
  login,

  /// OAuth 2 (Gmail, Outlook). The password is the access token.
  xoauth2,
}

/// Sends with an SMTP server.
/// ```
/// 'smtp': SmtpTransport(
///   host: 'smtp.example.com',
///   username: Env.get('MAIL_USERNAME'),
///   password: Env.get('MAIL_PASSWORD'),
/// ),
/// ```
class SmtpTransport extends Transport {
  SmtpTransport({
    required this.host,
    int? port,
    this.username,
    this.password,
    this.encryption = SmtpEncryption.starttls,
    this.allowInsecure = false,
    this.auth,
    this.localDomain = 'localhost',
    this.timeout = const Duration(seconds: 30),
    this.keepAlive = false,
    MimeBuilder? mime,
  }) : port =
           port ??
           switch (encryption) {
             SmtpEncryption.tls => 465,
             SmtpEncryption.starttls => 587,
             SmtpEncryption.none => 25,
           },
       mime = mime ?? MimeBuilder();

  final String host;

  /// Default: 465 for `tls`, 587 for `starttls`, 25 for `none`.
  final int port;

  /// Null: no login.
  final String? username;

  /// the password, or the access token for [SmtpAuth.xoauth2]
  final String? password;

  final SmtpEncryption encryption;

  /// Accept a TLS certificate that is not valid, eg. self-signed. Use it
  /// only for a test server.
  final bool allowInsecure;

  /// Null: PLAIN when the server lists it, else LOGIN.
  final SmtpAuth? auth;

  /// the name of this machine, for EHLO
  final String localDomain;

  /// how long to wait to connect, and for each reply
  final Duration timeout;

  /// Keep the connection open after a send, and use it for the next
  /// message. [close] ends it. Good when you send many emails.
  final bool keepAlive;

  final MimeBuilder mime;

  SmtpConnection? _connection;
  Future<void> _last = Future<void>.value();

  @override
  Future<SentMessage> send(Message message) {
    // one message at a time on the connection
    Future<SentMessage> result = _last.then((_) => _send(message));
    _last = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<SentMessage> _send(Message message) async {
    MimeMessage raw = mime.build(message);
    SmtpConnection? open = _connection;
    if (open != null && !open.isClosed) {
      try {
        await open.command('RSET', <int>[250]);
      } catch (_) {
        // the server closed the old connection: open a new one
        await open.close();
        open = null;
      }
    } else {
      open = null;
    }
    SmtpConnection c = open ?? await _connect();
    _connection = keepAlive ? c : null;
    try {
      await SmtpProtocol.sendMail(
        c,
        from: message.from!.email,
        recipients: message.recipients.map((Address a) => a.email).toList(),
        mime: raw.text,
      );
    } catch (_) {
      _connection = null;
      await c.close();
      rethrow;
    }
    if (!keepAlive) await _quit(c);
    return SentMessage(message, messageId: raw.messageId, raw: raw.text);
  }

  Future<SmtpConnection> _connect() async {
    Socket socket;
    try {
      socket = encryption == SmtpEncryption.tls
          ? await SecureSocket.connect(
              host,
              port,
              onBadCertificate: (_) => allowInsecure,
              timeout: timeout,
            )
          : await Socket.connect(host, port, timeout: timeout);
    } catch (error) {
      throw MailException('SMTP: can not connect to $host:$port: $error');
    }
    SmtpConnection c = SmtpConnection(
      socket,
      socket,
      timeout: timeout,
      socket: socket,
    );
    try {
      await c.expect(<int>[220], 'greeting');
      await SmtpProtocol.hello(c, localDomain);
      if (encryption == SmtpEncryption.starttls) {
        if (!c.extensions.contains('STARTTLS')) {
          throw MailException('SMTP: $host does not support STARTTLS');
        }
        await c.command('STARTTLS', <int>[220]);
        await c.upgrade(allowInsecure: allowInsecure, host: host);
        await SmtpProtocol.hello(c, localDomain);
      }
      if (username != null) await _login(c);
    } catch (_) {
      await c.close();
      rethrow;
    }
    return c;
  }

  Future<void> _login(SmtpConnection c) async {
    String user = username!;
    String pass = password ?? '';
    String b64(String text) => base64.encode(utf8.encode(text));
    SmtpAuth method = auth ?? _pick(c.extensions);
    switch (method) {
      case SmtpAuth.plain:
        await c.command('AUTH PLAIN ${b64('\u0000$user\u0000$pass')}', <int>[
          235,
        ], what: 'AUTH PLAIN');
      case SmtpAuth.login:
        await c.command('AUTH LOGIN', <int>[334]);
        await c.command(b64(user), <int>[334], what: 'AUTH LOGIN user');
        await c.command(b64(pass), <int>[235], what: 'AUTH LOGIN password');
      case SmtpAuth.xoauth2:
        String token = b64('user=$user\u0001auth=Bearer $pass\u0001\u0001');
        c.write('AUTH XOAUTH2 $token\r\n');
        SmtpReply reply = await c.read();
        if (reply.code == 334) {
          // the server sent the error as a challenge: answer with an
          // empty line to get the final error
          await c.command('', <int>[235], what: 'AUTH XOAUTH2');
        } else if (reply.code != 235) {
          throw MailException(
            'SMTP: AUTH XOAUTH2 failed: $reply',
            statusCode: reply.code,
            body: reply.text,
          );
        }
    }
  }

  static SmtpAuth _pick(List<String> extensions) {
    String line = extensions.firstWhere(
      (String e) => e.startsWith('AUTH ') || e.startsWith('AUTH='),
      orElse: () => '',
    );
    List<String> methods = line.substring(line.isEmpty ? 0 : 5).split(' ');
    if (!methods.contains('PLAIN') && methods.contains('LOGIN')) {
      return SmtpAuth.login;
    }
    return SmtpAuth.plain;
  }

  Future<void> _quit(SmtpConnection c) async {
    try {
      await c.command('QUIT', <int>[221]);
    } catch (_) {
      // the mail is sent: a bad QUIT does not matter
    }
    await c.close();
  }

  /// Ends the open connection of [keepAlive].
  @override
  Future<void> close() async {
    await _last;
    SmtpConnection? c = _connection;
    _connection = null;
    if (c != null && !c.isClosed) await _quit(c);
  }
}
