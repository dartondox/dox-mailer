import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A message the fake server got.
class ReceivedMail {
  ReceivedMail(this.from, this.recipients, this.data);

  final String from;
  final List<String> recipients;

  /// the DATA text, with the dot-stuffing removed
  final String data;
}

/// A small SMTP server on 127.0.0.1 for the tests. No real network.
class FakeSmtpServer {
  FakeSmtpServer._(
    this._server,
    this.context, {
    required this.startTls,
    required this.authMethods,
    required this.users,
  });

  /// [implicitTls]: TLS from the start. [startTls]: offer STARTTLS.
  static Future<FakeSmtpServer> start({
    bool implicitTls = false,
    bool startTls = false,
    String authMethods = 'PLAIN LOGIN XOAUTH2',
    Map<String, String> users = const <String, String>{'ann': 'secret'},
  }) async {
    SecurityContext context = SecurityContext()
      ..useCertificateChain('test/fixtures/cert.pem')
      ..usePrivateKey('test/fixtures/key.pem');
    Stream<Socket> server = implicitTls
        ? await SecureServerSocket.bind(
            InternetAddress.loopbackIPv4,
            0,
            context,
          )
        : await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    FakeSmtpServer fake = FakeSmtpServer._(
      server,
      context,
      startTls: startTls,
      authMethods: authMethods,
      users: users,
    );
    fake._sub = server.listen(fake._handle);
    return fake;
  }

  final Stream<Socket> _server;
  final SecurityContext context;
  final bool startTls;
  final String authMethods;
  final Map<String, String> users;
  late StreamSubscription<Socket> _sub;

  final List<String> commands = <String>[];
  final List<ReceivedMail> mails = <ReceivedMail>[];
  int connections = 0;

  /// commands that get this reply instead of the normal one
  final Map<String, String> failOn = <String, String>{};

  int get port {
    Stream<Socket> s = _server;
    return s is ServerSocket ? s.port : (s as SecureServerSocket).port;
  }

  Future<void> close() async {
    await _sub.cancel();
    Stream<Socket> s = _server;
    if (s is ServerSocket) await s.close();
    if (s is SecureServerSocket) await s.close();
  }

  Future<void> _handle(Socket socket) async {
    connections++;
    _Session session = _Session(socket);
    session.reply('220 fake.test ESMTP');
    String? from;
    List<String> rcpt = <String>[];
    bool secure = socket is SecureSocket;
    try {
      while (true) {
        String line = await session.line();
        commands.add(line);
        String upper = line.toUpperCase();
        String? fail = failOn.keys
            .where((String k) => upper.startsWith(k))
            .map((String k) => failOn[k]!)
            .firstOrNull;
        if (fail != null) {
          session.reply(fail);
          continue;
        }
        if (upper.startsWith('EHLO')) {
          session.reply('250-fake.test');
          if (startTls && !secure) session.reply('250-STARTTLS');
          session.reply('250-AUTH $authMethods');
          session.reply('250 8BITMIME');
        } else if (upper == 'STARTTLS') {
          session.reply('220 go ahead');
          await session.upgrade(context);
          secure = true;
        } else if (upper.startsWith('AUTH PLAIN ')) {
          List<String> parts = utf8
              .decode(base64.decode(line.substring(11)))
              .split('\u0000');
          session.reply(_ok(parts[1], parts[2]) ? '235 ok' : '535 bad');
        } else if (upper == 'AUTH LOGIN') {
          session.reply('334 VXNlcm5hbWU6');
          String user = utf8.decode(base64.decode(await session.line()));
          session.reply('334 UGFzc3dvcmQ6');
          String pass = utf8.decode(base64.decode(await session.line()));
          session.reply(_ok(user, pass) ? '235 ok' : '535 bad');
        } else if (upper.startsWith('AUTH XOAUTH2 ')) {
          String text = utf8.decode(base64.decode(line.substring(13)));
          Match? m = RegExp('^user=(.*)\u0001auth=Bearer (.*)\u0001\u0001\$')
              .firstMatch(text);
          if (m != null && _ok(m.group(1)!, m.group(2)!)) {
            session.reply('235 ok');
          } else {
            session.reply('334 eyJzdGF0dXMiOiI0MDEifQ==');
            await session.line();
            session.reply('535 bad token');
          }
        } else if (upper.startsWith('MAIL FROM:')) {
          from = line.substring(10).replaceAll(RegExp('[<>]'), '');
          rcpt = <String>[];
          session.reply('250 ok');
        } else if (upper.startsWith('RCPT TO:')) {
          rcpt.add(line.substring(8).replaceAll(RegExp('[<>]'), ''));
          session.reply('250 ok');
        } else if (upper == 'DATA') {
          session.reply('354 send it');
          List<String> lines = <String>[];
          while (true) {
            String data = await session.line();
            if (data == '.') break;
            lines.add(data.startsWith('.') ? data.substring(1) : data);
          }
          mails.add(ReceivedMail(from!, rcpt, '${lines.join('\r\n')}\r\n'));
          session.reply('250 queued');
        } else if (upper == 'RSET') {
          session.reply('250 ok');
        } else if (upper == 'QUIT') {
          session.reply('221 bye');
          await session.close();
          return;
        } else {
          session.reply('500 what');
        }
      }
    } catch (_) {
      // the client went away, or the TLS handshake failed
      socket.destroy();
    }
  }

  bool _ok(String user, String pass) => users[user] == pass;
}

class _Session {
  _Session(Socket socket) : _socket = socket {
    _listen(socket);
  }

  Socket _socket;
  late StreamSubscription<List<int>> _sub;
  final List<int> _buffer = <int>[];
  final List<String> _lines = <String>[];
  Completer<void>? _wait;
  bool _done = false;

  void _listen(Stream<List<int>> input) {
    _sub = input.listen(
      (List<int> data) {
        _buffer.addAll(data);
        int end;
        while ((end = _buffer.indexOf(10)) >= 0) {
          List<int> line = _buffer.sublist(0, end);
          _buffer.removeRange(0, end + 1);
          if (line.isNotEmpty && line.last == 13) line.removeLast();
          _lines.add(utf8.decode(line));
        }
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
      onError: (Object _) {
        _done = true;
        _wake();
      },
    );
  }

  void _wake() {
    Completer<void>? w = _wait;
    _wait = null;
    w?.complete();
  }

  Future<String> line() async {
    while (_lines.isEmpty) {
      if (_done) throw StateError('closed');
      Completer<void> w = Completer<void>();
      _wait = w;
      await w.future;
    }
    return _lines.removeAt(0);
  }

  void reply(String text) => _socket.add(utf8.encode('$text\r\n'));

  Future<void> upgrade(SecurityContext context) async {
    _sub.pause();
    SecureSocket secure = await SecureSocket.secureServer(_socket, context);
    unawaited(_sub.cancel());
    _socket = secure;
    _listen(secure);
  }

  Future<void> close() async {
    await _socket.close();
    _socket.destroy();
  }
}
