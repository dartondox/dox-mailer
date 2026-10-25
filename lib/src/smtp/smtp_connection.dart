import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../mail_exception.dart';

/// A reply of an SMTP server: a code and its lines of text.
class SmtpReply {
  const SmtpReply(this.code, this.lines);

  final int code;
  final List<String> lines;

  String get text => lines.join('\n');

  @override
  String toString() => '$code $text';
}

/// One SMTP conversation over a byte stream: a socket, or the stdin and
/// stdout of `sendmail -bs`.
class SmtpConnection {
  SmtpConnection(
    Stream<List<int>> input,
    this._output, {
    required this.timeout,
    this.socket,
  }) {
    _listen(input);
  }

  /// the socket, when the connection is a socket. STARTTLS needs it.
  Socket? socket;

  final Duration timeout;
  StreamSink<List<int>> _output;
  late StreamSubscription<List<int>> _subscription;

  final List<int> _buffer = <int>[];
  final List<String> _lines = <String>[];
  Completer<void>? _waiting;
  Object? _error;
  bool _done = false;

  /// the keywords of the last EHLO reply, upper case: `STARTTLS`,
  /// `AUTH PLAIN LOGIN`, ...
  List<String> extensions = <String>[];

  bool get isClosed => _done;

  void _listen(Stream<List<int>> input) {
    _subscription = input.listen(
      (List<int> data) {
        _buffer.addAll(data);
        int end;
        while ((end = _buffer.indexOf(10)) >= 0) {
          List<int> line = _buffer.sublist(0, end);
          _buffer.removeRange(0, end + 1);
          if (line.isNotEmpty && line.last == 13) line.removeLast();
          _lines.add(utf8.decode(line, allowMalformed: true));
        }
        _wake();
      },
      onError: (Object error) {
        _error = error;
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
    );
  }

  void _wake() {
    Completer<void>? waiting = _waiting;
    _waiting = null;
    waiting?.complete();
  }

  Future<String> _readLine() async {
    while (_lines.isEmpty) {
      if (_error != null) {
        throw MailException('SMTP: connection error: $_error');
      }
      if (_done) throw MailException('SMTP: the server closed the connection');
      Completer<void> waiting = Completer<void>();
      _waiting = waiting;
      await waiting.future.timeout(
        timeout,
        onTimeout: () => throw MailException(
          'SMTP: no answer in ${timeout.inSeconds} seconds',
        ),
      );
    }
    return _lines.removeAt(0);
  }

  /// Reads one reply, with all its lines.
  Future<SmtpReply> read() async {
    List<String> lines = <String>[];
    while (true) {
      String line = await _readLine();
      if (line.length < 3 || int.tryParse(line.substring(0, 3)) == null) {
        throw MailException('SMTP: bad reply "$line"');
      }
      lines.add(line.length > 4 ? line.substring(4) : '');
      if (line.length < 4 || line[3] != '-') {
        return SmtpReply(int.parse(line.substring(0, 3)), lines);
      }
    }
  }

  /// Reads a reply and throws a [MailException] when its code is not in
  /// [ok].
  Future<SmtpReply> expect(List<int> ok, String what) async {
    SmtpReply reply = await read();
    if (!ok.contains(reply.code)) {
      throw MailException(
        'SMTP: $what failed: $reply',
        statusCode: reply.code,
        body: reply.text,
      );
    }
    return reply;
  }

  /// Sends [line] with CRLF, and reads the reply. [what] is for the error
  /// message, so a password is never in it.
  Future<SmtpReply> command(String line, List<int> ok, {String? what}) {
    write('$line\r\n');
    return expect(ok, what ?? line);
  }

  void write(String text) => _output.add(utf8.encode(text));

  void writeBytes(List<int> bytes) => _output.add(bytes);

  /// Turns the socket into a TLS socket (after `STARTTLS`).
  Future<void> upgrade({required bool allowInsecure, String? host}) async {
    Socket? plain = socket;
    if (plain == null) throw MailException('SMTP: STARTTLS needs a socket');
    _subscription.pause();
    SecureSocket secure;
    try {
      secure = await SecureSocket.secure(
        plain,
        host: host,
        onBadCertificate: (_) => allowInsecure,
      ).timeout(timeout);
    } catch (error) {
      plain.destroy();
      throw MailException('SMTP: TLS failed: $error');
    }
    unawaited(_subscription.cancel());
    _buffer.clear();
    _lines.clear();
    socket = secure;
    _output = secure;
    _listen(secure);
  }

  /// Closes the connection, with no QUIT.
  Future<void> close() async {
    _done = true;
    try {
      await _output.close();
    } catch (_) {
      // already closed
    }
    socket?.destroy();
    await _subscription.cancel();
  }
}
