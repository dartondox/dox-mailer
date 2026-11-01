import 'address.dart';
import 'attachment.dart';
import 'mail_exception.dart';
import 'message.dart';

/// Throws a [MailException] when a part of [message] could add new mail
/// headers: a bad address, or a line break in the subject, a header or
/// an attachment's content type or cid.
///
/// It does not ask for a from address, a recipient or a body, so a
/// direct transport send works as in 3.0.0. `Message.check` does both.
/// Not exported: it is only for the built-in transports.
void checkHeaders(Message message) {
  for (Address address in <Address>[
    ?message.from,
    ...message.recipients,
    ...message.replyTo,
  ]) {
    address.check();
  }
  if (message.subject.contains(RegExp(r'[\r\n]'))) {
    throw MailException('the subject has a line break');
  }
  message.headers.forEach((String name, String value) {
    if (!RegExp(r'^[!-9;-~]+$').hasMatch(name)) {
      throw MailException('"$name" is not a valid header name');
    }
    if (value.contains(RegExp(r'[\r\n]'))) {
      throw MailException('the "$name" header has a line break');
    }
  });
  // the content type and cid go into MIME headers as they are. The file
  // name is encoded, so it is safe.
  for (Attachment file in message.attachments) {
    for (String? value in <String?>[file.contentType, file.cid]) {
      if (value != null && value.contains(RegExp(r'[\r\n]'))) {
        throw MailException(
          'the attachment "${file.filename}" has a line break',
        );
      }
    }
  }
}
