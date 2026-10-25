import 'dart:convert';

import 'package:http/http.dart' as http;

import '../address.dart';
import '../attachment.dart';
import '../message.dart';
import 'http_transport.dart';

/// Sends with the Resend API.
/// ```
/// 'resend': ResendTransport(apiKey: Env.get('RESEND_API_KEY')),
/// ```
/// [Message.metadata] and [Message.tags] go to Resend as tags. A tag of
/// [Message.tags] gets the value `true`.
class ResendTransport extends HttpTransport {
  ResendTransport({required this.apiKey, Uri? endpoint, http.Client? client})
    : endpoint = endpoint ?? Uri.parse('https://api.resend.com/emails'),
      super(client);

  final String apiKey;

  /// Default: `https://api.resend.com/emails`
  final Uri endpoint;

  @override
  String get provider => 'Resend';

  @override
  Future<SentMessage> send(Message message) async {
    List<String> list(List<Address> a) =>
        a.map((Address x) => x.toString()).toList();
    List<Map<String, String>> tags = <Map<String, String>>[
      for (String tag in message.tags)
        <String, String>{'name': tag, 'value': 'true'},
      for (MapEntry<String, String> e in message.metadata.entries)
        <String, String>{'name': e.key, 'value': e.value},
    ];
    Map<String, Object> data = <String, Object>{
      'from': message.from.toString(),
      'to': list(message.to),
      if (message.cc.isNotEmpty) 'cc': list(message.cc),
      if (message.bcc.isNotEmpty) 'bcc': list(message.bcc),
      if (message.replyTo.isNotEmpty) 'reply_to': list(message.replyTo),
      'subject': message.subject,
      if (message.text != null) 'text': message.text!,
      if (message.html != null) 'html': message.html!,
      if (message.headers.isNotEmpty) 'headers': message.headers,
      if (message.attachments.isNotEmpty)
        'attachments': message.attachments
            .map(
              (Attachment a) => <String, String>{
                'filename': a.filename,
                'content': base64.encode(a.bytes),
                'content_type': a.contentType,
                if (a.cid != null) 'content_id': a.cid!,
              },
            )
            .toList(),
      if (tags.isNotEmpty) 'tags': tags,
    };
    http.Response response = await post(
      endpoint,
      headers: <String, String>{
        'authorization': 'Bearer $apiKey',
        'content-type': 'application/json',
      },
      body: jsonEncode(data),
    );
    Object? id = HttpTransport.json(response)['id'];
    return SentMessage(message, messageId: id?.toString());
  }
}
