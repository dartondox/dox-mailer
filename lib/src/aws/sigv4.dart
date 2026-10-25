import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Signs AWS requests with Signature Version 4.
/// See https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv.html
/// ```
/// AwsSigV4 signer = AwsSigV4(
///   accessKeyId: 'AKID...',
///   secretAccessKey: '...',
///   region: 'us-east-1',
///   service: 'ses',
/// );
/// Map<String, String> headers = signer.sign(
///   method: 'POST',
///   uri: uri,
///   headers: <String, String>{'content-type': 'application/json'},
///   body: bytes,
/// );
/// ```
class AwsSigV4 {
  AwsSigV4({
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.region,
    required this.service,
    this.sessionToken,
  });

  final String accessKeyId;
  final String secretAccessKey;
  final String region;
  final String service;

  /// for temporary credentials (eg. from a role)
  final String? sessionToken;

  /// The [headers] plus `host`, `x-amz-date`, `x-amz-security-token`
  /// (with a session token) and `authorization`. Send all of them.
  Map<String, String> sign({
    required String method,
    required Uri uri,
    Map<String, String> headers = const <String, String>{},
    List<int> body = const <int>[],
    DateTime? time,
  }) {
    String amzDate = _amzDate((time ?? DateTime.now()).toUtc());
    String day = amzDate.substring(0, 8);

    Map<String, String> all = <String, String>{};
    headers.forEach((String name, String value) {
      all[name.toLowerCase()] = value;
    });
    all.putIfAbsent(
      'host',
      () => uri.hasPort && !_defaultPort(uri)
          ? '${uri.host}:${uri.port}'
          : uri.host,
    );
    all['x-amz-date'] = amzDate;
    if (sessionToken != null) all['x-amz-security-token'] = sessionToken!;

    List<String> names = all.keys.toList()..sort();
    String canonicalHeaders = names
        .map((String n) => '$n:${_trim(all[n]!)}\n')
        .join();
    String signedHeaders = names.join(';');

    String canonicalRequest = <String>[
      method.toUpperCase(),
      _canonicalPath(uri),
      _canonicalQuery(uri),
      canonicalHeaders,
      signedHeaders,
      sha256.convert(body).toString(),
    ].join('\n');

    String scope = '$day/$region/$service/aws4_request';
    String stringToSign = <String>[
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    List<int> key = _hmac(utf8.encode('AWS4$secretAccessKey'), day);
    key = _hmac(key, region);
    key = _hmac(key, service);
    key = _hmac(key, 'aws4_request');
    String signature = Hmac(
      sha256,
      key,
    ).convert(utf8.encode(stringToSign)).toString();

    all['authorization'] =
        'AWS4-HMAC-SHA256 Credential=$accessKeyId/$scope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';
    return all;
  }

  static List<int> _hmac(List<int> key, String data) {
    return Hmac(sha256, key).convert(utf8.encode(data)).bytes;
  }

  static bool _defaultPort(Uri uri) {
    return (uri.scheme == 'https' && uri.port == 443) ||
        (uri.scheme == 'http' && uri.port == 80);
  }

  static String _amzDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}'
        'T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
  }

  static String _trim(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _canonicalPath(Uri uri) {
    String path = uri.path.isEmpty ? '/' : uri.path;
    return path
        .split('/')
        .map((String s) => encode(Uri.decodeComponent(s)))
        .join('/');
  }

  static String _canonicalQuery(Uri uri) {
    if (uri.query.isEmpty) return '';
    List<List<String>> pairs = <List<String>>[];
    uri.queryParametersAll.forEach((String key, List<String> values) {
      for (String value in values) {
        pairs.add(<String>[encode(key), encode(value)]);
      }
    });
    pairs.sort((List<String> a, List<String> b) {
      int byKey = a[0].compareTo(b[0]);
      return byKey != 0 ? byKey : a[1].compareTo(b[1]);
    });
    return pairs.map((List<String> p) => '${p[0]}=${p[1]}').join('&');
  }

  /// URI encoding of AWS: every byte but `A-Z a-z 0-9 - _ . ~` is `%XX`.
  static String encode(String value) {
    StringBuffer out = StringBuffer();
    for (int b in utf8.encode(value)) {
      bool keep =
          (b >= 0x41 && b <= 0x5a) ||
          (b >= 0x61 && b <= 0x7a) ||
          (b >= 0x30 && b <= 0x39) ||
          b == 0x2d ||
          b == 0x5f ||
          b == 0x2e ||
          b == 0x7e;
      out.write(
        keep
            ? String.fromCharCode(b)
            : '%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}',
      );
    }
    return out.toString();
  }
}
