import 'address.dart';
import 'attachment.dart';
import 'mail_exception.dart';
import 'message.dart';

final RegExp _lineBreak = RegExp(r'[\r\n]');

/// Throws a [MailException] when a part of [message] has a CR or LF, so
/// it could add new mail headers. It looks at the addresses and names,
/// the subject, the header names and values, and each attachment's
/// content type and cid.
///
/// It only looks for CR and LF. So a direct transport send takes the same
/// messages as in 3.0.0, eg. `Address('root')`. `Message.check` does the
/// full check. Not exported: it is only for the built-in transports.
void checkHeaders(Message message) {
  for (Address address in <Address>[
    ?message.from,
    ...message.recipients,
    ...message.replyTo,
  ]) {
    _noLineBreak(address.email, 'the address "${address.email}"');
    _noLineBreak(address.name, 'the name of "${address.email}"');
  }
  _noLineBreak(message.subject, 'the subject');
  message.headers.forEach((String name, String value) {
    _noLineBreak(name, 'the header name "$name"');
    _noLineBreak(value, 'the "$name" header');
  });
  // the content type and cid go into MIME headers as they are. The file
  // name is encoded, so it is safe.
  for (Attachment file in message.attachments) {
    _noLineBreak(file.contentType, 'the attachment "${file.filename}"');
    _noLineBreak(file.cid, 'the attachment "${file.filename}"');
  }
}

void _noLineBreak(String? value, String what) {
  if (value != null && value.contains(_lineBreak)) {
    throw MailException('$what has a line break');
  }
}
