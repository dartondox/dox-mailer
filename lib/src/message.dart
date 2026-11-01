import 'address.dart';
import 'attachment.dart';
import 'header_check.dart';
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

  /// Reads the map of [toJson], eg. in a queue worker.
  factory Message.fromJson(Map<String, Object?> json) {
    Object? from = json['from'];
    return Message(
      from: from == null ? null : Address.fromJson(_map(from)),
      to: _addresses(json['to']),
      cc: _addresses(json['cc']),
      bcc: _addresses(json['bcc']),
      replyTo: _addresses(json['replyTo']),
      subject: json['subject'] as String? ?? '',
      text: json['text'] as String?,
      html: json['html'] as String?,
      attachments: <Attachment>[
        for (Object? item
            in json['attachments'] as List<Object?>? ?? <Object?>[])
          Attachment.fromJson(_map(item)),
      ],
      headers: _strings(json['headers']),
      tags: <String>[
        for (Object? tag in json['tags'] as List<Object?>? ?? <Object?>[])
          tag as String,
      ],
      metadata: _strings(json['metadata']),
    );
  }

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

  /// The message as a JSON map, eg. to put it on a queue. Attachments
  /// are saved as base64, so the map holds the full files.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'from': from?.toJson(),
      'to': <Object?>[for (Address a in to) a.toJson()],
      'cc': <Object?>[for (Address a in cc) a.toJson()],
      'bcc': <Object?>[for (Address a in bcc) a.toJson()],
      'replyTo': <Object?>[for (Address a in replyTo) a.toJson()],
      'subject': subject,
      'text': text,
      'html': html,
      'attachments': <Object?>[for (Attachment a in attachments) a.toJson()],
      'headers': headers,
      'tags': tags,
      'metadata': metadata,
    };
  }

  static Map<String, Object?> _map(Object? value) {
    return Map<String, Object?>.from(value as Map<Object?, Object?>);
  }

  static List<Address> _addresses(Object? value) {
    return <Address>[
      for (Object? item in value as List<Object?>? ?? <Object?>[])
        Address.fromJson(_map(item)),
    ];
  }

  static Map<String, String> _strings(Object? value) {
    if (value == null) return <String, String>{};
    return Map<String, String>.from(value as Map<Object?, Object?>);
  }

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
  /// sender, no recipient, no body, or a bad address, header or
  /// attachment.
  void check() {
    if (from == null) {
      throw MailException('the message has no from address');
    }
    if (recipients.isEmpty) {
      throw MailException('the message has no recipient');
    }
    if (text == null && html == null) {
      throw MailException('the message has no text and no html');
    }
    for (Address address in <Address>[from!, ...recipients, ...replyTo]) {
      address.check();
    }
    for (String name in headers.keys) {
      if (!RegExp(r'^[!-9;-~]+$').hasMatch(name)) {
        throw MailException('"$name" is not a valid header name');
      }
    }
    checkHeaders(this);
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
