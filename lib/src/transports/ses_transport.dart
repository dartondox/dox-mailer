import 'dart:convert';

import 'package:http/http.dart' as http;

import '../address.dart';
import '../aws/sigv4.dart';
import '../message.dart';
import '../mime/mime_builder.dart';
import 'http_transport.dart';

/// Sends with Amazon SES, API v1 (`SendRawEmail`).
/// ```
/// 'ses': SesTransport(
///   key: Env.get('AWS_ACCESS_KEY_ID'),
///   secret: Env.get('AWS_SECRET_ACCESS_KEY'),
///   region: 'eu-west-1',
/// ),
/// ```
/// Use [SesV2Transport] for API v2. Both send the same MIME message.
/// [Message.metadata] goes to SES as message tags.
class SesTransport extends HttpTransport {
  SesTransport({
    required this.key,
    required this.secret,
    this.sessionToken,
    this.region = 'us-east-1',
    this.configurationSet,
    Uri? endpoint,
    http.Client? client,
    MimeBuilder? mime,
    DateTime Function()? clock,
  }) : endpoint = endpoint ?? Uri.parse('https://email.$region.amazonaws.com/'),
       mime = mime ?? MimeBuilder(),
       clock = clock ?? DateTime.now,
       super(client);

  /// the AWS access key id
  final String key;

  /// the AWS secret access key
  final String secret;

  /// for temporary credentials (eg. from a role)
  final String? sessionToken;

  final String region;

  /// the SES configuration set, to track events
  final String? configurationSet;

  /// the API address. Default: `https://email.<region>.amazonaws.com/`
  final Uri endpoint;

  final MimeBuilder mime;
  final DateTime Function() clock;

  @override
  String get provider => 'SES';

  AwsSigV4 get signer => AwsSigV4(
    accessKeyId: key,
    secretAccessKey: secret,
    sessionToken: sessionToken,
    region: region,
    service: 'ses',
  );

  /// POSTs a signed request and gives the response
  Future<http.Response> signedPost(Uri uri, String contentType, String body) {
    List<int> bytes = utf8.encode(body);
    Map<String, String> headers = signer.sign(
      method: 'POST',
      uri: uri,
      headers: <String, String>{'content-type': contentType},
      body: bytes,
      time: clock(),
    )..remove('host');
    return post(uri, headers: headers, body: bytes);
  }

  @override
  Future<SentMessage> send(Message message) async {
    MimeMessage raw = mime.build(message);
    Map<String, String> form = <String, String>{
      'Action': 'SendRawEmail',
      'Version': '2010-12-01',
      'Source': message.from!.email,
    };
    List<Address> recipients = message.recipients;
    for (int i = 0; i < recipients.length; i++) {
      form['Destinations.member.${i + 1}'] = recipients[i].email;
    }
    form['RawMessage.Data'] = base64.encode(raw.bytes);
    if (configurationSet != null) {
      form['ConfigurationSetName'] = configurationSet!;
    }
    int n = 0;
    message.metadata.forEach((String name, String value) {
      n++;
      form['Tags.member.$n.Name'] = name;
      form['Tags.member.$n.Value'] = value;
    });
    String body = form.entries
        .map(
          (MapEntry<String, String> e) =>
              '${AwsSigV4.encode(e.key)}=${AwsSigV4.encode(e.value)}',
        )
        .join('&');
    http.Response response = await signedPost(
      endpoint,
      'application/x-www-form-urlencoded; charset=utf-8',
      body,
    );
    Match? id = RegExp(r'<MessageId>([^<]+)</MessageId>')
        .firstMatch(response.body);
    return SentMessage(message, messageId: id?.group(1), raw: raw.text);
  }
}

/// Sends with Amazon SES, API v2 (`SendEmail` with `Raw` content).
/// It takes the same settings as [SesTransport].
class SesV2Transport extends SesTransport {
  SesV2Transport({
    required super.key,
    required super.secret,
    super.sessionToken,
    super.region,
    super.configurationSet,
    super.endpoint,
    super.client,
    super.mime,
    super.clock,
  });

  @override
  Future<SentMessage> send(Message message) async {
    MimeMessage raw = mime.build(message);
    List<String> emails(List<Address> list) =>
        list.map((Address a) => a.email).toList();
    Map<String, Object> data = <String, Object>{
      'FromEmailAddress': message.from!.email,
      'Destination': <String, List<String>>{
        if (message.to.isNotEmpty) 'ToAddresses': emails(message.to),
        if (message.cc.isNotEmpty) 'CcAddresses': emails(message.cc),
        if (message.bcc.isNotEmpty) 'BccAddresses': emails(message.bcc),
      },
      'Content': <String, Object>{
        'Raw': <String, String>{'Data': base64.encode(raw.bytes)},
      },
      'ConfigurationSetName': ?configurationSet,
      if (message.metadata.isNotEmpty)
        'EmailTags': message.metadata.entries
            .map(
              (MapEntry<String, String> e) => <String, String>{
                'Name': e.key,
                'Value': e.value,
              },
            )
            .toList(),
    };
    http.Response response = await signedPost(
      endpoint.resolve('/v2/email/outbound-emails'),
      'application/json',
      jsonEncode(data),
    );
    Object? id = HttpTransport.json(response)['MessageId'];
    return SentMessage(message, messageId: id?.toString(), raw: raw.text);
  }
}
