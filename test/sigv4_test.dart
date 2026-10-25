import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

/// The example keys of the AWS docs. Not real keys.
AwsSigV4 _signer(String region, String service) => AwsSigV4(
  accessKeyId: 'AKIDEXAMPLE',
  secretAccessKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
  region: region,
  service: service,
);

void main() {
  DateTime time = DateTime.utc(2015, 8, 30, 12, 36);

  test('AWS test suite: get-vanilla', () {
    Map<String, String> headers = _signer('us-east-1', 'service').sign(
      method: 'GET',
      uri: Uri.parse('https://example.amazonaws.com/'),
      time: time,
    );
    expect(headers['x-amz-date'], '20150830T123600Z');
    expect(headers['host'], 'example.amazonaws.com');
    expect(
      headers['authorization'],
      'AWS4-HMAC-SHA256 '
      'Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, '
      'SignedHeaders=host;x-amz-date, '
      'Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31',
    );
  });

  test('AWS docs example: IAM ListUsers', () {
    Map<String, String> headers = _signer('us-east-1', 'iam').sign(
      method: 'GET',
      uri: Uri.parse(
        'https://iam.amazonaws.com/?Action=ListUsers&Version=2010-05-08',
      ),
      headers: <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
      },
      time: time,
    );
    expect(
      headers['authorization'],
      'AWS4-HMAC-SHA256 '
      'Credential=AKIDEXAMPLE/20150830/us-east-1/iam/aws4_request, '
      'SignedHeaders=content-type;host;x-amz-date, '
      'Signature=5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7',
    );
  });

  test('a session token is a signed header', () {
    Map<String, String> headers =
        AwsSigV4(
          accessKeyId: 'AKIDEXAMPLE',
          secretAccessKey: 'secret',
          sessionToken: 'token123',
          region: 'eu-west-1',
          service: 'ses',
        ).sign(
          method: 'POST',
          uri: Uri.parse('https://email.eu-west-1.amazonaws.com/'),
          time: time,
        );
    expect(headers['x-amz-security-token'], 'token123');
    expect(
      headers['authorization'],
      contains('SignedHeaders=host;x-amz-date;x-amz-security-token,'),
    );
  });

  test('encode keeps only unreserved chars', () {
    expect(AwsSigV4.encode('a b/c~d_e.f-g=é'), 'a%20b%2Fc~d_e.f-g%3D%C3%A9');
  });
}
