import 'dart:convert';

import 'package:http/http.dart' as http;

import '../address.dart';
import '../attachment.dart';
import '../message.dart';
import 'http_transport.dart';

/// Sends with the Postmark API.
/// ```
/// 'postmark': PostmarkTransport(
///   serverToken: Env.get('POSTMARK_TOKEN'),
///   messageStream: 'outbound',
/// ),
/// ```
/// Postmark takes one tag: the first of [Message.tags].
/// [Message.metadata] goes to Postmark as metadata.
class PostmarkTransport extends HttpTransport {
  PostmarkTransport({
    required this.serverToken,
    this.messageStream,
    Uri? endpoint,
    http.Client? client,
  }) : endpoint = endpoint ?? Uri.parse('https://api.postmarkapp.com/email'),
       super(client);

  final String serverToken;

  /// the message stream, eg. `outbound` or `broadcast`. Null: the
  /// default stream of the server.
  final String? messageStream;

  /// Default: `https://api.postmarkapp.com/email`
  final Uri endpoint;

  @override
  String get provider => 'Postmark';

  @override
  Future<SentMessage> send(Message message) async {
    String join(List<Address> a) => a.map((Address x) => '$x').join(', ');
    Map<String, Object> data = <String, Object>{
      'From': message.from.toString(),
      'To': join(message.to),
      if (message.cc.isNotEmpty) 'Cc': join(message.cc),
      if (message.bcc.isNotEmpty) 'Bcc': join(message.bcc),
      if (message.replyTo.isNotEmpty) 'ReplyTo': join(message.replyTo),
      'Subject': message.subject,
      if (message.text != null) 'TextBody': message.text!,
      if (message.html != null) 'HtmlBody': message.html!,
      if (message.headers.isNotEmpty)
        'Headers': message.headers.entries
            .map(
              (MapEntry<String, String> e) => <String, String>{
                'Name': e.key,
                'Value': e.value,
              },
            )
            .toList(),
      if (message.tags.isNotEmpty) 'Tag': message.tags.first,
      if (message.metadata.isNotEmpty) 'Metadata': message.metadata,
      'MessageStream': ?messageStream,
      if (message.attachments.isNotEmpty)
        'Attachments': message.attachments
            .map(
              (Attachment a) => <String, String>{
                'Name': a.filename,
                'Content': base64.encode(a.bytes),
                'ContentType': a.contentType,
                if (a.cid != null) 'ContentID': 'cid:${a.cid}',
              },
            )
            .toList(),
    };
    http.Response response = await post(
      endpoint,
      headers: <String, String>{
        'accept': 'application/json',
        'content-type': 'application/json',
        'x-postmark-server-token': serverToken,
      },
      body: jsonEncode(data),
    );
    Object? id = HttpTransport.json(response)['MessageID'];
    return SentMessage(message, messageId: id?.toString());
  }
}
