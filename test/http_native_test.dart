import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

/// The HTTP transports with their own client (the native client of
/// dox_http_client) and a real server on a socket. The other tests pass a
/// MockClient.
void main() {
  late HttpServer server;
  late Uri base;
  int status = 200;
  String answer = '{"id":"id-1"}';
  List<HttpRequest> requests = <HttpRequest>[];
  List<Uint8List> bodies = <Uint8List>[];
  Set<int> connections = <int>{};

  setUp(() async {
    status = 200;
    answer = '{"id":"id-1"}';
    requests.clear();
    bodies.clear();
    connections.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((HttpRequest request) async {
      connections.add(request.connectionInfo!.remotePort);
      BytesBuilder bytes = BytesBuilder(copy: false);
      await request.forEach(bytes.add);
      requests.add(request);
      bodies.add(bytes.takeBytes());
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(answer);
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Message message() => Message(
    from: const Address('app@example.com', 'My App'),
    to: <Address>[const Address('ann@example.com', 'Ann')],
    subject: 'Wélcome',
    text: 'Hello Ann',
    attachments: <Attachment>[
      Attachment(Uint8List(300000)..fillRange(0, 300000, 65), 'big.txt'),
    ],
  );

  test('Resend: a JSON body goes out, the answer comes back', () async {
    ResendTransport resend = ResendTransport(
      apiKey: 're_test',
      endpoint: base.resolve('/emails'),
    );
    addTearDown(resend.close);
    expect((await resend.send(message())).messageId, 'id-1');
    HttpRequest request = requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/emails');
    expect(request.headers.value('authorization'), 'Bearer re_test');
    expect(request.headers.value('content-type'), 'application/json');
    expect(request.headers.contentLength, bodies.single.length);
    Map<String, dynamic> json =
        jsonDecode(utf8.decode(bodies.single)) as Map<String, dynamic>;
    expect(json['subject'], 'Wélcome');
    expect(json['to'], <String>['Ann <ann@example.com>']);
    // the next mails use the same connection
    await resend.send(message());
    await resend.send(message());
    expect(connections, hasLength(1));
  });

  test('Mailgun: a multipart body goes out whole', () async {
    MailgunTransport mailgun = MailgunTransport(
      apiKey: 'key-test',
      domain: 'mg.example.com',
      endpoint: base,
    );
    addTearDown(mailgun.close);
    expect((await mailgun.send(message())).messageId, isNotEmpty);
    HttpRequest request = requests.single;
    expect(request.uri.path, contains('mg.example.com'));
    expect(
      request.headers.value('content-type'),
      startsWith('multipart/form-data; boundary='),
    );
    expect(request.headers.contentLength, bodies.single.length);
    expect(bodies.single.length, greaterThan(300000));
    String text = latin1.decode(bodies.single);
    expect(text, contains('filename="big.txt"'));
    expect(text, contains('A' * 1000));
  });

  test(
    'an error status and a server that is down are a MailException',
    () async {
      status = 422;
      answer = '{"message":"Invalid from"}';
      ResendTransport resend = ResendTransport(
        apiKey: 're_test',
        endpoint: base.resolve('/emails'),
      );
      addTearDown(resend.close);
      await expectLater(
        resend.send(message()),
        throwsA(
          isA<MailException>()
              .having((MailException e) => e.statusCode, 'statusCode', 422)
              .having((MailException e) => e.body, 'body', contains('Invalid')),
        ),
      );

      ServerSocket socket = await ServerSocket.bind('127.0.0.1', 0);
      int port = socket.port;
      await socket.close();
      ResendTransport down = ResendTransport(
        apiKey: 're_test',
        endpoint: Uri.parse('http://127.0.0.1:$port/emails'),
      );
      addTearDown(down.close);
      await expectLater(
        down.send(message()),
        throwsA(
          isA<MailException>().having(
            (MailException e) => e.toString(),
            'text',
            contains('the request failed'),
          ),
        ),
      );
    },
  );
}
