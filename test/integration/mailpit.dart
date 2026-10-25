import 'dart:convert';

import 'helpers.dart';

/// Reads messages from the REST API of Mailpit.
/// See https://mailpit.axllent.org/docs/api-v1/
class Mailpit {
  Mailpit(this.api);

  /// eg. `http://localhost:8025`
  final Uri api;

  /// Finds the one message with [id] in its subject, and reads it.
  Future<ReadMail> read(String id) async {
    List<String> ids = await find(id, 1);
    return readById(ids.single);
  }

  /// Waits until [count] messages have [id] in the subject, and gives
  /// their Mailpit ids.
  Future<List<String>> find(String id, int count) {
    return eventually(() async {
      Map<String, dynamic> found = await getJson(
        api.replace(
          path: '/api/v1/search',
          queryParameters: <String, String>{'query': 'subject:$id'},
        ),
      ) as Map<String, dynamic>;
      List<dynamic> messages = found['messages'] as List<dynamic>;
      if (messages.length < count) return null;
      return messages
          .map((dynamic m) => (m as Map<String, dynamic>)['ID'] as String)
          .toList();
    }, '$count message(s) with "$id" in Mailpit at $api');
  }

  Future<ReadMail> readById(String mailpitId) async {
    Uri message = api.replace(path: '/api/v1/message/$mailpitId');
    Map<String, dynamic> m = await getJson(message) as Map<String, dynamic>;
    String raw = utf8.decode(
      await getBytes(message.replace(path: '${message.path}/raw')),
    );
    List<String> emails(Object? list) => <String>[
      for (dynamic a in (list as List<dynamic>? ?? <dynamic>[]))
        (a as Map<String, dynamic>)['Address'] as String,
    ];
    Map<String, List<int>> files = <String, List<int>>{};
    for (dynamic a in m['Attachments'] as List<dynamic>) {
      Map<String, dynamic> file = a as Map<String, dynamic>;
      files[file['FileName'] as String] = await getBytes(
        message.replace(path: '${message.path}/part/${file['PartID']}'),
      );
    }
    return ReadMail(
      from: (m['From'] as Map<String, dynamic>)['Address'] as String,
      to: emails(m['To']),
      cc: emails(m['Cc']),
      subject: m['Subject'] as String,
      text: m['Text'] as String,
      html: m['HTML'] as String,
      files: files,
      headerNames: clientHeaders(raw),
      // Mailpit lists the envelope recipients that are not in To or Cc
      // as Bcc
      envelope: <String>[
        ...emails(m['To']),
        ...emails(m['Cc']),
        ...emails(m['Bcc']),
      ],
    );
  }
}

/// The header names that the client sent. Mailpit puts its own headers
/// on top: Bcc (from the envelope), Return-Path and Received. The
/// headers of the client come after the last Received header.
Set<String> clientHeaders(String raw) {
  String text = raw.replaceAll('\r\n', '\n');
  int end = text.indexOf('\n\n');
  List<String> names = text
      .substring(0, end < 0 ? text.length : end)
      .replaceAll(RegExp(r'\n[ \t]+'), ' ')
      .split('\n')
      .map((String line) => line.split(':').first.trim().toLowerCase())
      .toList();
  return names.sublist(names.lastIndexOf('received') + 1).toSet();
}
