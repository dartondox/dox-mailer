import '../attachment.dart';
import '../message.dart';
import '../transport.dart';

/// Prints the message and sends nothing. Good for local work.
/// ```
/// 'log': LogTransport(),
/// ```
class LogTransport extends Transport {
  /// [output] gets the text. Null: `print`.
  LogTransport({void Function(String text)? output})
    : _output = output ?? print;

  final void Function(String text) _output;

  @override
  Future<SentMessage> send(Message message) async {
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
    out.writeln(message.text ?? message.html);
    out.write('--- end ---');
    _output(out.toString());
    return SentMessage(message);
  }
}
