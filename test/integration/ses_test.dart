@Tags(<String>['integration'])
library;

import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// SES against two free AWS fakes:
///
/// - LocalStack (LOCALSTACK_URL) for API v1. Its free image has no SES
///   v2, and its list of sent mail has no recipients.
/// - moto (MOTO_URL) for API v1 and v2. It keeps the recipients, so the
///   Bcc check runs there.
///
/// Both read the raw MIME back, and the test parses it.
void main() {
  const String sender = 'app@example.com';

  SesTransport v1(String url) =>
      SesTransport(key: 'test', secret: 'test', endpoint: Uri.parse(url));

  SesTransport v2(String url) =>
      SesV2Transport(key: 'test', secret: 'test', endpoint: Uri.parse(url));

  /// The fakes only send from a verified address.
  Future<void> verify(SesTransport ses) async {
    await ses.signedPost(
      ses.endpoint,
      'application/x-www-form-urlencoded; charset=utf-8',
      'Action=VerifyEmailIdentity&Version=2010-12-01'
          '&EmailAddress=${Uri.encodeQueryComponent(sender)}',
    );
  }

  /// Sends the sample message and gives its id and the SES message id.
  Future<(String, String)> send(SesTransport ses) async {
    String id = newId();
    try {
      await verify(ses);
      SentMessage sent = await ses.send(sampleMessage(id));
      expect(sent.messageId, isNotEmpty);
      return (id, sent.messageId!);
    } finally {
      await ses.close();
    }
  }

  group('SES with LocalStack', () {
    String url = env('LOCALSTACK_URL') ?? 'http://localhost:4566';

    /// the raw MIME of the message with [messageId]
    Future<String> raw(String messageId) async {
      Map<String, dynamic> data = await getJson(
        Uri.parse(url).resolve('/_aws/ses?id=$messageId'),
      ) as Map<String, dynamic>;
      Map<String, dynamic> message =
          (data['messages'] as List<dynamic>).single as Map<String, dynamic>;
      expect(message['Source'], sender);
      return message['RawData'] as String;
    }

    test('v1 SendRawEmail', () async {
      var (String id, String messageId) = await send(v1(url));
      expectSample(parseMime(await raw(messageId)), id);
    });
  }, skip: skipUnless('LOCALSTACK_URL', 'LocalStack'));

  group('SES with moto', () {
    String url = env('MOTO_URL') ?? 'http://localhost:5000';

    /// the raw MIME and the recipients of the message with [messageId]
    Future<ReadMail> read(String messageId) async {
      Map<String, dynamic> data = await getJson(
        Uri.parse(url).resolve('/moto-api/data.json'),
      ) as Map<String, dynamic>;
      List<dynamic> sent =
          (data['ses'] as Map<String, dynamic>)['RawMessage'] as List<dynamic>;
      Map<String, dynamic> message = sent.singleWhere(
        (dynamic m) => (m as Map<String, dynamic>)['id'] == messageId,
      ) as Map<String, dynamic>;
      expect(message['source'], sender);
      return parseMime(
        message['raw_data'] as String,
        envelope: (message['destinations'] as List<dynamic>).cast<String>(),
      );
    }

    test('v1 SendRawEmail', () async {
      var (String id, String messageId) = await send(v1(url));
      expectSample(await read(messageId), id);
    });

    test('v2 SendEmail', () async {
      var (String id, String messageId) = await send(v2(url));
      expectSample(await read(messageId), id);
    });
  }, skip: skipUnless('MOTO_URL', 'moto'));
}
