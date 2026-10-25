import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../address.dart';
import '../attachment.dart';
import '../message.dart';
import 'http_transport.dart';

/// Sends with the Azure Communication Services Email REST API. It signs
/// each request with the access key (HMAC-SHA256).
/// ```
/// 'azure': AzureTransport(
///   endpoint: 'https://my-app.europe.communication.azure.com',
///   accessKey: Env.get('AZURE_EMAIL_KEY'),
/// ),
/// 'azure': AzureTransport.fromConnectionString(
///   Env.get('AZURE_EMAIL_CONNECTION_STRING'),
/// ),
/// ```
/// Azure has no tags or metadata. Inline images (an attachment with a
/// cid) need an [apiVersion] that supports them, eg. `2025-09-01`.
class AzureTransport extends HttpTransport {
  AzureTransport({
    required String endpoint,
    required this.accessKey,
    this.apiVersion = '2023-03-31',
    this.disableTracking = false,
    http.Client? client,
    DateTime Function()? clock,
  }) : endpoint = Uri.parse(endpoint),
       clock = clock ?? DateTime.now,
       super(client);

  /// Reads `endpoint=https://...;accesskey=...`, the connection string
  /// of the Azure portal.
  factory AzureTransport.fromConnectionString(
    String connectionString, {
    String apiVersion = '2023-03-31',
    bool disableTracking = false,
    http.Client? client,
    DateTime Function()? clock,
  }) {
    Map<String, String> parts = <String, String>{};
    for (String part in connectionString.split(';')) {
      int equal = part.indexOf('=');
      if (equal < 1) continue;
      parts[part.substring(0, equal).trim().toLowerCase()] = part
          .substring(equal + 1)
          .trim();
    }
    String? endpoint = parts['endpoint'];
    String? key = parts['accesskey'];
    if (endpoint == null || key == null) {
      throw ArgumentError.value(
        '***',
        'connectionString',
        'needs endpoint=...;accesskey=...',
      );
    }
    return AzureTransport(
      endpoint: endpoint,
      accessKey: key,
      apiVersion: apiVersion,
      disableTracking: disableTracking,
      client: client,
      clock: clock,
    );
  }

  /// the resource address, eg. `https://my-app.communication.azure.com`
  final Uri endpoint;

  /// the access key of the resource, as base64 text
  final String accessKey;

  final String apiVersion;

  /// turn off open and click tracking for the emails
  final bool disableTracking;

  final DateTime Function() clock;

  @override
  String get provider => 'Azure';

  @override
  Future<SentMessage> send(Message message) async {
    Map<String, Object> data = <String, Object>{
      'senderAddress': message.from!.email,
      'content': <String, String>{
        'subject': message.subject,
        if (message.text != null) 'plainText': message.text!,
        if (message.html != null) 'html': message.html!,
      },
      'recipients': <String, Object>{
        'to': _list(message.to),
        if (message.cc.isNotEmpty) 'cc': _list(message.cc),
        if (message.bcc.isNotEmpty) 'bcc': _list(message.bcc),
      },
      if (message.replyTo.isNotEmpty) 'replyTo': _list(message.replyTo),
      if (message.headers.isNotEmpty) 'headers': message.headers,
      if (message.attachments.isNotEmpty)
        'attachments': message.attachments
            .map(
              (Attachment a) => <String, String>{
                'name': a.filename,
                'contentType': a.contentType,
                'contentInBase64': base64.encode(a.bytes),
                if (a.cid != null) 'contentId': a.cid!,
              },
            )
            .toList(),
      if (disableTracking) 'userEngagementTrackingDisabled': true,
    };
    List<int> body = utf8.encode(jsonEncode(data));
    String base = endpoint.toString().replaceAll(RegExp(r'/+$'), '');
    Uri uri = Uri.parse('$base/emails:send?api-version=$apiVersion');
    http.Response response = await post(
      uri,
      headers: <String, String>{
        'content-type': 'application/json',
        ...signHeaders(uri, body),
      },
      body: body,
    );
    Object? id = HttpTransport.json(response)['id'];
    return SentMessage(message, messageId: id?.toString());
  }

  /// The auth headers of a POST to [uri] with [body]: `x-ms-date`,
  /// `x-ms-content-sha256` and `authorization`.
  Map<String, String> signHeaders(Uri uri, List<int> body) {
    String date = HttpDate.format(clock().toUtc());
    String hash = base64.encode(sha256.convert(body).bytes);
    String pathAndQuery = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    String toSign = 'POST\n$pathAndQuery\n$date;${uri.authority};$hash';
    String signature = base64.encode(
      Hmac(sha256, base64.decode(accessKey)).convert(utf8.encode(toSign)).bytes,
    );
    return <String, String>{
      'x-ms-date': date,
      'x-ms-content-sha256': hash,
      'authorization':
          'HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256'
          '&Signature=$signature',
    };
  }

  static List<Map<String, String>> _list(List<Address> list) {
    return list
        .map(
          (Address a) => <String, String>{
            'address': a.email,
            if (a.name != null) 'displayName': a.name!,
          },
        )
        .toList();
  }
}
