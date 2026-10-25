import 'dart:convert';

import 'package:http/http.dart' as http;

import '../address.dart';
import '../attachment.dart';
import '../message.dart';
import 'http_transport.dart';

/// The Mailgun region of your domain.
enum MailgunRegion { us, eu }

/// Sends with the Mailgun API.
/// ```
/// 'mailgun': MailgunTransport(
///   apiKey: Env.get('MAILGUN_API_KEY'),
///   domain: 'mg.example.com',
///   region: MailgunRegion.eu,
/// ),
/// ```
/// [Message.tags] go to Mailgun as tags (`o:tag`). [Message.metadata]
/// goes as variables (`v:name`).
class MailgunTransport extends HttpTransport {
  MailgunTransport({
    required this.apiKey,
    required this.domain,
    this.region = MailgunRegion.us,
    Uri? endpoint,
    http.Client? client,
  }) : endpoint =
           endpoint ??
           Uri.parse(
             region == MailgunRegion.eu
                 ? 'https://api.eu.mailgun.net'
                 : 'https://api.mailgun.net',
           ),
       super(client);

  final String apiKey;

  /// your sending domain, eg. `mg.example.com`
  final String domain;

  final MailgunRegion region;

  /// The API address. Default: `https://api.mailgun.net`, or
  /// `https://api.eu.mailgun.net` for [MailgunRegion.eu].
  final Uri endpoint;

  @override
  String get provider => 'Mailgun';

  @override
  Future<SentMessage> send(Message message) async {
    String base = endpoint.toString().replaceAll(RegExp(r'/+$'), '');
    http.MultipartRequest request = http.MultipartRequest(
      'POST',
      Uri.parse('$base/v3/${Uri.encodeComponent(domain)}/messages'),
    );
    request.headers['authorization'] =
        'Basic ${base64.encode(utf8.encode('api:$apiKey'))}';
    String join(List<Address> a) => a.map((Address x) => '$x').join(', ');
    Map<String, String> fields = request.fields;
    fields['from'] = message.from.toString();
    fields['to'] = join(message.to);
    if (message.cc.isNotEmpty) fields['cc'] = join(message.cc);
    if (message.bcc.isNotEmpty) fields['bcc'] = join(message.bcc);
    if (message.replyTo.isNotEmpty) {
      fields['h:Reply-To'] = join(message.replyTo);
    }
    fields['subject'] = message.subject;
    if (message.text != null) fields['text'] = message.text!;
    if (message.html != null) fields['html'] = message.html!;
    message.headers.forEach((String name, String value) {
      fields['h:$name'] = value;
    });
    message.metadata.forEach((String name, String value) {
      fields['v:$name'] = value;
    });
    // a field name can come once in `fields`: more tags go in as parts
    for (String tag in message.tags) {
      request.files.add(http.MultipartFile.fromString('o:tag', tag));
    }
    for (Attachment file in message.attachments) {
      request.files.add(
        http.MultipartFile.fromBytes(
          file.isInline ? 'inline' : 'attachment',
          file.bytes,
          // Mailgun uses the file name as the cid of an inline file
          filename: file.cid ?? file.filename,
        ),
      );
    }
    http.Response response = await sendRequest(request);
    Object? id = HttpTransport.json(response)['id'];
    return SentMessage(message, messageId: id?.toString());
  }
}
