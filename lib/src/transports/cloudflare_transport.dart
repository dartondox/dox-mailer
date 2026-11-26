import 'dart:convert';

import 'package:http/http.dart' as http;

import '../address.dart';
import '../attachment.dart';
import '../header_check.dart';
import '../message.dart';
import 'http_transport.dart';

/// Sends with the Cloudflare Email Service API.
/// ```
/// 'cloudflare': CloudflareTransport(
///   accountId: Env.get('CLOUDFLARE_ACCOUNT_ID'),
///   apiToken: Env.get('CLOUDFLARE_API_TOKEN'),
/// ),
/// ```
/// The token needs the `Email Sending Write` permission. Cloudflare takes
/// one reply-to address: the first of [Message.replyTo]. It has no tags
/// and no metadata, so [Message.tags] and [Message.metadata] are skipped.
class CloudflareTransport extends HttpTransport {
  CloudflareTransport({
    required this.accountId,
    required this.apiToken,
    Uri? endpoint,
    http.Client? client,
  }) : endpoint =
           endpoint ??
           Uri.parse(
             'https://api.cloudflare.com/client/v4/accounts/'
             '${Uri.encodeComponent(accountId)}/email/sending/send',
           ),
       super(client);

  final String accountId;
  final String apiToken;

  /// Default:
  /// `https://api.cloudflare.com/client/v4/accounts/{accountId}/email/sending/send`
  final Uri endpoint;

  @override
  String get provider => 'Cloudflare';

  @override
  Future<SentMessage> send(Message message) async {
    checkHeaders(message);
    Map<String, String> address(Address a) => <String, String>{
      'address': a.email,
      'name': ?a.name,
    };
    List<Map<String, String>> list(List<Address> a) => a.map(address).toList();
    Map<String, Object> data = <String, Object>{
      if (message.from != null) 'from': address(message.from!),
      'to': list(message.to),
      if (message.cc.isNotEmpty) 'cc': list(message.cc),
      if (message.bcc.isNotEmpty) 'bcc': list(message.bcc),
      if (message.replyTo.isNotEmpty)
        'reply_to': address(message.replyTo.first),
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
                'type': a.contentType,
                'disposition': a.cid == null ? 'attachment' : 'inline',
                'content_id': ?a.cid,
              },
            )
            .toList(),
    };
    http.Response response = await post(
      endpoint,
      headers: <String, String>{
        'authorization': 'Bearer $apiToken',
        'content-type': 'application/json',
      },
      body: jsonEncode(data),
    );
    Object? result = HttpTransport.json(response)['result'];
    Object? id = result is Map<String, dynamic> ? result['message_id'] : null;
    return SentMessage(message, messageId: id?.toString());
  }
}
