import 'package:dox_core/dox_core.dart' show Logger;

import '../attachment.dart';
import '../message.dart';
import '../transport.dart';
import '../header_check.dart';

/// Prints the message and sends nothing. Good for local work.
/// ```
/// 'log': LogTransport(),
/// 'log': LogTransport(useLogger: true, bothBodies: true),
/// ```
class LogTransport extends Transport {
  /// [output] gets the text. Null: `print`.
  ///
  /// [useLogger] true: write the text with `Logger.info`, the app log.
  /// The logger is off by default: set `LoggerConfig(enabled: true)`, or
  /// nothing is written. The logger level must allow `info`.
  /// When the logger throws (eg. Dox is not set up), the text is printed.
  /// [output] wins when both are set.
  ///
  /// [bothBodies] true: show the text body and the HTML body when the
  /// message has both. False: show only the text body, or the HTML body
  /// when there is no text.
  LogTransport({
    void Function(String text)? output,
    bool useLogger = false,
    this.bothBodies = false,
  }) : _output = output ?? (useLogger ? _logOrPrint : print);

  final void Function(String text) _output;

  /// show both the text and the HTML body
  final bool bothBodies;

  /// a log transport must not make `send()` fail, so a logger error
  /// prints the text instead. Same as the `onSent` hook error in `Mail`.
  static void _logOrPrint(String text) {
    try {
      Logger.info(text);
    } catch (_) {
      print(text);
    }
  }

  @override
  Future<SentMessage> send(Message message) async {
    checkHeaders(message);
    StringBuffer out = StringBuffer('--- mail ---\n');
    out.writeln('From: ${message.from}');
    out.writeln('To: ${message.to.join(', ')}');
    if (message.cc.isNotEmpty) out.writeln('Cc: ${message.cc.join(', ')}');
    if (message.bcc.isNotEmpty) out.writeln('Bcc: ${message.bcc.join(', ')}');
    if (message.replyTo.isNotEmpty) {
      out.writeln('Reply-To: ${message.replyTo.join(', ')}');
    }
    out.writeln('Subject: ${message.subject}');
    message.headers.forEach((String name, String value) {
      out.writeln('$name: $value');
    });
    for (Attachment file in message.attachments) {
      out.writeln(
        'Attachment: ${file.filename} (${file.contentType}, '
        '${file.bytes.length} bytes)',
      );
    }
    out.writeln();
    if (bothBodies && message.text != null && message.html != null) {
      out.writeln('--- text ---');
      out.writeln(message.text);
      out.writeln('--- html ---');
      out.writeln(message.html);
    } else {
      out.writeln(message.text ?? message.html);
    }
    out.write('--- end ---');
    _output(out.toString());
    return SentMessage(message);
  }
}
