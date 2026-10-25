import 'address.dart';
import 'attachment.dart';
import 'mail_exception.dart';

/// An email.
/// ```
/// Message(
///   to: <Address>[Address('ann@example.com', 'Ann')],
///   subject: 'Welcome',
///   text: 'Hello Ann',
///   html: '<p>Hello Ann</p>',
/// )
/// ```
/// When [from] is null, the mailer uses `MailConfig.from`.
class Message {
  Message({
    this.from,
    this.to = const <Address>[],
    this.cc = const <Address>[],
    this.bcc = const <Address>[],
    this.replyTo = const <Address>[],
    this.subject = '',
    this.text,
    this.html,
    this.attachments = const <Attachment>[],
    this.headers = const <String, String>{},
    this.tags = const <String>[],
    this.metadata = const <String, String>{},
  });

  final Address? from;
  final List<Address> to;
  final List<Address> cc;
  final List<Address> bcc;
  final List<Address> replyTo;
  final String subject;

  /// the plain text body
  final String? text;

  /// the HTML body
  final String? html;

  final List<Attachment> attachments;

  /// extra headers, like `X-Campaign`. They are added as they are.
  final Map<String, String> headers;

  /// Tags for the provider, to group emails in its reports. Mailgun,
  /// Postmark (the first tag) and Resend use them. Others skip them.
  final List<String> tags;

  /// Key and value data for the provider, eg. a user id. SES, Mailgun,
  /// Postmark and Resend use it. Others skip it.
  final Map<String, String> metadata;

  /// every recipient: [to], [cc] and [bcc]
  List<Address> get recipients => <Address>[...to, ...cc, ...bcc];

  /// A copy with other values.
  Message copyWith({
    Address? from,
    List<Address>? to,
    List<Address>? cc,
    List<Address>? bcc,
    List<Address>? replyTo,
    String? subject,
    String? text,
    String? html,
    List<Attachment>? attachments,
    Map<String, String>? headers,
    List<String>? tags,
    Map<String, String>? metadata,
  }) {
    return Message(
      from: from ?? this.from,
      to: to ?? this.to,
      cc: cc ?? this.cc,
      bcc: bcc ?? this.bcc,
      replyTo: replyTo ?? this.replyTo,
      subject: subject ?? this.subject,
      text: text ?? this.text,
      html: html ?? this.html,
      attachments: attachments ?? this.attachments,
      headers: headers ?? this.headers,
      tags: tags ?? this.tags,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Throws a [MailException] when the message can not be sent: no
  /// sender, no recipient, no body, or a bad address or header.
  void check() {
    Address? sender = from;
    if (sender == null) {
      throw MailException('the message has no from address');
    }
    if (recipients.isEmpty) {
      throw MailException('the message has no recipient');
    }
    if (text == null && html == null) {
      throw MailException('the message has no text and no html');
    }
    sender.check();
    for (Address address in <Address>[...recipients, ...replyTo]) {
      address.check();
    }
    if (subject.contains(RegExp(r'[\r\n]'))) {
      throw MailException('the subject has a line break');
    }
    headers.forEach((String name, String value) {
      if (!RegExp(r'^[!-9;-~]+$').hasMatch(name)) {
        throw MailException('"$name" is not a valid header name');
      }
      if (value.contains(RegExp(r'[\r\n]'))) {
        throw MailException('the "$name" header has a line break');
      }
    });
  }
}

/// What a transport gives back after it sent a [Message].
class SentMessage {
  const SentMessage(this.message, {this.messageId, this.raw});

  /// the message that was sent, with the default from address filled in
  final Message message;

  /// The id of the message. For SMTP and sendmail it is the `Message-ID`
  /// header. For SES and the other APIs it is the id the provider gives.
  final String? messageId;

  /// the MIME text of the message, when the transport made one
  final String? raw;
}
