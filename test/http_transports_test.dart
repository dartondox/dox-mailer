import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dox_mailer/dox_mailer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final DateTime _time = DateTime.utc(2026, 10, 25, 12);

Message _message() => Message(
  from: const Address('app@example.com', 'My App'),
  to: <Address>[const Address('ann@example.com', 'Ann')],
  cc: <Address>[const Address('bob@example.com')],
  bcc: <Address>[const Address('boss@example.com')],
  replyTo: <Address>[const Address('help@example.com')],
  subject: 'Welcome',
  text: 'Hello Ann',
  html: '<p>Hello Ann</p><img src="cid:logo">',
  attachments: <Attachment>[
    Attachment(utf8.encode('PDF'), 'invoice.pdf'),
    Attachment(<int>[1, 2, 3], 'logo.png', cid: 'logo'),
  ],
  headers: <String, String>{'X-Campaign': 'fall'},
  tags: <String>['welcome', 'onboarding'],
  metadata: <String, String>{'user_id': '42'},
);

/// A MockClient that keeps the last request and answers [status] [body].
class _Recorder {
  _Recorder(int status, String body, {Map<String, String>? headers}) {
    client = MockClient((http.Request request) async {
      requests.add(request);
      return http.Response(
        body,
        status,
        headers: headers ?? <String, String>{},
      );
    });
  }

  late final MockClient client;
  final List<http.Request> requests = <http.Request>[];

  http.Request get last => requests.last;
  Map<String, dynamic> get json =>
      jsonDecode(last.body) as Map<String, dynamic>;
}

void main() {
  group('SES v1', () {
    test('posts SendRawEmail with a SigV4 signature', () async {
      _Recorder r = _Recorder(
        200,
        '<SendRawEmailResponse><SendRawEmailResult><MessageId>ses-1</MessageId>'
        '</SendRawEmailResult></SendRawEmailResponse>',
      );
      SesTransport ses = SesTransport(
        key: 'AKIDEXAMPLE',
        secret: 'test-secret',
        sessionToken: 'tok',
        region: 'eu-west-1',
        configurationSet: 'tracking',
        client: r.client,
        clock: () => _time,
      );
      SentMessage sent = await ses.send(_message());

      expect(sent.messageId, 'ses-1');
      http.Request req = r.last;
      expect(req.method, 'POST');
      expect(req.url.toString(), 'https://email.eu-west-1.amazonaws.com/');
      expect(
        req.headers['content-type'],
        'application/x-www-form-urlencoded; charset=utf-8',
      );
      expect(req.headers['x-amz-date'], '20261025T120000Z');
      expect(req.headers['x-amz-security-token'], 'tok');

      Map<String, String> form = Uri.splitQueryString(req.body);
      expect(form['Action'], 'SendRawEmail');
      expect(form['Version'], '2010-12-01');
      expect(form['Source'], 'app@example.com');
      expect(form['Destinations.member.1'], 'ann@example.com');
      expect(form['Destinations.member.2'], 'bob@example.com');
      expect(form['Destinations.member.3'], 'boss@example.com');
      expect(form['ConfigurationSetName'], 'tracking');
      expect(form['Tags.member.1.Name'], 'user_id');
      expect(form['Tags.member.1.Value'], '42');
      String raw = utf8.decode(base64.decode(form['RawMessage.Data']!));
      expect(raw, contains('Subject: Welcome\r\n'));
      expect(raw, contains('Content-ID: <logo>'));
      expect(raw, isNot(contains('boss@example.com')));
      expect(sent.raw, raw);

      Map<String, String> expected =
          AwsSigV4(
            accessKeyId: 'AKIDEXAMPLE',
            secretAccessKey: 'test-secret',
            sessionToken: 'tok',
            region: 'eu-west-1',
            service: 'ses',
          ).sign(
            method: 'POST',
            uri: req.url,
            headers: <String, String>{
              'content-type': req.headers['content-type']!,
            },
            body: req.bodyBytes,
            time: _time,
          );
      expect(req.headers['authorization'], expected['authorization']);
      expect(
        req.headers['authorization'],
        startsWith(
          'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20261025/eu-west-1/ses/aws4_request, '
          'SignedHeaders=content-type;host;x-amz-date;x-amz-security-token, Signature=',
        ),
      );
    });

    test('an error answer is a MailException', () async {
      _Recorder r = _Recorder(
        400,
        '<Error><Message>Email address is not verified.</Message></Error>',
      );
      SesTransport ses = SesTransport(key: 'k', secret: 's', client: r.client);
      await expectLater(
        ses.send(_message()),
        throwsA(
          isA<MailException>()
              .having((MailException e) => e.statusCode, 'statusCode', 400)
              .having(
                (MailException e) => e.message,
                'message',
                contains('not verified'),
              ),
        ),
      );
    });
  });

  test('SES v2 posts SendEmail with raw content', () async {
    _Recorder r = _Recorder(200, '{"MessageId":"ses-2"}');
    SesV2Transport ses = SesV2Transport(
      key: 'AKIDEXAMPLE',
      secret: 'test-secret',
      region: 'us-east-2',
      configurationSet: 'tracking',
      client: r.client,
      clock: () => _time,
    );
    SentMessage sent = await ses.send(_message());

    expect(sent.messageId, 'ses-2');
    http.Request req = r.last;
    expect(
      req.url.toString(),
      'https://email.us-east-2.amazonaws.com/v2/email/outbound-emails',
    );
    expect(req.headers['content-type'], 'application/json');
    expect(
      req.headers['authorization'],
      startsWith(
        'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20261025/us-east-2/ses/aws4_request, '
        'SignedHeaders=content-type;host;x-amz-date, Signature=',
      ),
    );
    Map<String, String> expected =
        AwsSigV4(
          accessKeyId: 'AKIDEXAMPLE',
          secretAccessKey: 'test-secret',
          region: 'us-east-2',
          service: 'ses',
        ).sign(
          method: 'POST',
          uri: req.url,
          headers: <String, String>{'content-type': 'application/json'},
          body: req.bodyBytes,
          time: _time,
        );
    expect(req.headers['authorization'], expected['authorization']);

    Map<String, dynamic> body = r.json;
    expect(body['FromEmailAddress'], 'app@example.com');
    expect(body['Destination'], <String, dynamic>{
      'ToAddresses': <String>['ann@example.com'],
      'CcAddresses': <String>['bob@example.com'],
      'BccAddresses': <String>['boss@example.com'],
    });
    expect(body['ConfigurationSetName'], 'tracking');
    expect(body['EmailTags'], <Map<String, String>>[
      <String, String>{'Name': 'user_id', 'Value': '42'},
    ]);
    String raw = utf8.decode(
      base64.decode(
        (body['Content'] as Map<String, dynamic>)['Raw']['Data'] as String,
      ),
    );
    expect(raw, contains('From: My App <app@example.com>\r\n'));
  });

  group('Azure', () {
    // a made-up key, as base64
    String key = base64.encode(utf8.encode('azure-test-key'));

    test('posts the email with an HMAC-SHA256 signature', () async {
      _Recorder r = _Recorder(202, '{"id":"op-1","status":"Running"}');
      AzureTransport azure = AzureTransport(
        endpoint: 'https://my-app.communication.azure.com/',
        accessKey: key,
        client: r.client,
        clock: () => _time,
      );
      SentMessage sent = await azure.send(_message());

      expect(sent.messageId, 'op-1');
      http.Request req = r.last;
      expect(
        req.url.toString(),
        'https://my-app.communication.azure.com/emails:send?api-version=2023-03-31',
      );
      expect(req.headers['x-ms-date'], 'Sun, 25 Oct 2026 12:00:00 GMT');
      String hash = base64.encode(sha256.convert(req.bodyBytes).bytes);
      expect(req.headers['x-ms-content-sha256'], hash);
      String toSign =
          'POST\n/emails:send?api-version=2023-03-31\n'
          'Sun, 25 Oct 2026 12:00:00 GMT;my-app.communication.azure.com;$hash';
      String signature = base64.encode(
        Hmac(
          sha256,
          utf8.encode('azure-test-key'),
        ).convert(utf8.encode(toSign)).bytes,
      );
      expect(
        req.headers['authorization'],
        'HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=$signature',
      );

      Map<String, dynamic> body = r.json;
      expect(body['senderAddress'], 'app@example.com');
      expect(body['content'], <String, String>{
        'subject': 'Welcome',
        'plainText': 'Hello Ann',
        'html': '<p>Hello Ann</p><img src="cid:logo">',
      });
      expect(body['recipients'], <String, dynamic>{
        'to': <Map<String, String>>[
          <String, String>{'address': 'ann@example.com', 'displayName': 'Ann'},
        ],
        'cc': <Map<String, String>>[
          <String, String>{'address': 'bob@example.com'},
        ],
        'bcc': <Map<String, String>>[
          <String, String>{'address': 'boss@example.com'},
        ],
      });
      expect(body['replyTo'], <Map<String, String>>[
        <String, String>{'address': 'help@example.com'},
      ]);
      expect(body['headers'], <String, String>{'X-Campaign': 'fall'});
      expect(body['attachments'], <Map<String, String>>[
        <String, String>{
          'name': 'invoice.pdf',
          'contentType': 'application/pdf',
          'contentInBase64': base64.encode(utf8.encode('PDF')),
        },
        <String, String>{
          'name': 'logo.png',
          'contentType': 'image/png',
          'contentInBase64': 'AQID',
          'contentId': 'logo',
        },
      ]);
    });

    test('reads a connection string', () async {
      _Recorder r = _Recorder(202, '{"id":"op-2"}');
      AzureTransport azure = AzureTransport.fromConnectionString(
        'endpoint=https://other.communication.azure.com/;accesskey=$key',
        client: r.client,
      );
      expect(azure.endpoint.host, 'other.communication.azure.com');
      expect(azure.accessKey, key);
      await azure.send(_message());
      expect(r.last.url.host, 'other.communication.azure.com');
      expect(
        () => AzureTransport.fromConnectionString('endpoint=https://x'),
        throwsArgumentError,
      );
    });
  });

  test('Resend', () async {
    _Recorder r = _Recorder(200, '{"id":"re-1"}');
    ResendTransport resend = ResendTransport(
      apiKey: 're_test',
      client: r.client,
    );
    SentMessage sent = await resend.send(_message());

    expect(sent.messageId, 're-1');
    http.Request req = r.last;
    expect(req.url.toString(), 'https://api.resend.com/emails');
    expect(req.headers['authorization'], 'Bearer re_test');
    expect(req.headers['content-type'], 'application/json');
    expect(r.json, <String, dynamic>{
      'from': 'My App <app@example.com>',
      'to': <String>['Ann <ann@example.com>'],
      'cc': <String>['bob@example.com'],
      'bcc': <String>['boss@example.com'],
      'reply_to': <String>['help@example.com'],
      'subject': 'Welcome',
      'text': 'Hello Ann',
      'html': '<p>Hello Ann</p><img src="cid:logo">',
      'headers': <String, String>{'X-Campaign': 'fall'},
      'attachments': <Map<String, String>>[
        <String, String>{
          'filename': 'invoice.pdf',
          'content': base64.encode(utf8.encode('PDF')),
          'content_type': 'application/pdf',
        },
        <String, String>{
          'filename': 'logo.png',
          'content': 'AQID',
          'content_type': 'image/png',
          'content_id': 'logo',
        },
      ],
      'tags': <Map<String, String>>[
        <String, String>{'name': 'welcome', 'value': 'true'},
        <String, String>{'name': 'onboarding', 'value': 'true'},
        <String, String>{'name': 'user_id', 'value': '42'},
      ],
    });
  });

  test('Resend error is a MailException', () async {
    _Recorder r = _Recorder(422, '{"message":"Invalid from"}');
    ResendTransport resend = ResendTransport(
      apiKey: 're_test',
      client: r.client,
    );
    await expectLater(
      resend.send(_message()),
      throwsA(
        isA<MailException>().having(
          (MailException e) => e.body,
          'body',
          contains('Invalid from'),
        ),
      ),
    );
  });

  group('Mailgun', () {
    test('posts a multipart form, US region', () async {
      _Recorder r = _Recorder(
        200,
        '{"id":"<mg-1@mg.example.com>","message":"Queued"}',
      );
      MailgunTransport mailgun = MailgunTransport(
        apiKey: 'key-test',
        domain: 'mg.example.com',
        client: r.client,
      );
      SentMessage sent = await mailgun.send(_message());

      expect(sent.messageId, '<mg-1@mg.example.com>');
      http.Request req = r.last;
      expect(
        req.url.toString(),
        'https://api.mailgun.net/v3/mg.example.com/messages',
      );
      expect(
        req.headers['authorization'],
        'Basic ${base64.encode(utf8.encode('api:key-test'))}',
      );
      expect(
        req.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      String body = req.body;
      void field(String name, String value) {
        expect(body, contains('name="$name"\r\n\r\n$value\r\n'), reason: name);
      }

      field('from', 'My App <app@example.com>');
      field('to', 'Ann <ann@example.com>');
      field('cc', 'bob@example.com');
      field('bcc', 'boss@example.com');
      field('h:Reply-To', 'help@example.com');
      field('subject', 'Welcome');
      field('text', 'Hello Ann');
      field('h:X-Campaign', 'fall');
      field('v:user_id', '42');
      expect(RegExp(r'name="o:tag"').allMatches(body), hasLength(2));
      expect(body, contains('welcome'));
      expect(body, contains('onboarding'));
      expect(body, contains('name="attachment"; filename="invoice.pdf"'));
      expect(body, contains('name="inline"; filename="logo"'));
    });

    test('EU region', () async {
      _Recorder r = _Recorder(200, '{"id":"x"}');
      MailgunTransport mailgun = MailgunTransport(
        apiKey: 'key-test',
        domain: 'mg.example.com',
        region: MailgunRegion.eu,
        client: r.client,
      );
      await mailgun.send(_message());
      expect(
        r.last.url.toString(),
        'https://api.eu.mailgun.net/v3/mg.example.com/messages',
      );
    });
  });

  test('Postmark', () async {
    _Recorder r = _Recorder(200, '{"ErrorCode":0,"MessageID":"pm-1"}');
    PostmarkTransport postmark = PostmarkTransport(
      serverToken: 'pm-token',
      messageStream: 'outbound',
      client: r.client,
    );
    SentMessage sent = await postmark.send(_message());

    expect(sent.messageId, 'pm-1');
    http.Request req = r.last;
    expect(req.url.toString(), 'https://api.postmarkapp.com/email');
    expect(req.headers['x-postmark-server-token'], 'pm-token');
    expect(req.headers['accept'], 'application/json');
    expect(r.json, <String, dynamic>{
      'From': 'My App <app@example.com>',
      'To': 'Ann <ann@example.com>',
      'Cc': 'bob@example.com',
      'Bcc': 'boss@example.com',
      'ReplyTo': 'help@example.com',
      'Subject': 'Welcome',
      'TextBody': 'Hello Ann',
      'HtmlBody': '<p>Hello Ann</p><img src="cid:logo">',
      'Headers': <Map<String, String>>[
        <String, String>{'Name': 'X-Campaign', 'Value': 'fall'},
      ],
      'Tag': 'welcome',
      'Metadata': <String, String>{'user_id': '42'},
      'MessageStream': 'outbound',
      'Attachments': <Map<String, String>>[
        <String, String>{
          'Name': 'invoice.pdf',
          'Content': base64.encode(utf8.encode('PDF')),
          'ContentType': 'application/pdf',
        },
        <String, String>{
          'Name': 'logo.png',
          'Content': 'AQID',
          'ContentType': 'image/png',
          'ContentID': 'cid:logo',
        },
      ],
    });
  });

  test('a failed request is a MailException', () async {
    MockClient client = MockClient((http.Request _) async {
      throw http.ClientException('no network');
    });
    PostmarkTransport postmark = PostmarkTransport(
      serverToken: 't',
      client: client,
    );
    await expectLater(
      postmark.send(_message()),
      throwsA(
        isA<MailException>().having(
          (MailException e) => e.message,
          'message',
          contains('no network'),
        ),
      ),
    );
  });
}
