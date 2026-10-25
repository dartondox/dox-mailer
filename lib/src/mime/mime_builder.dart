import 'dart:convert';
import 'dart:math';

import '../address.dart';
import '../attachment.dart';
import '../message.dart';
import 'mime_encoding.dart';

/// A message as MIME text, ready for SMTP, SES or sendmail.
class MimeMessage {
  const MimeMessage(this.messageId, this.text);

  /// the `Message-ID` header, with `<>`
  final String messageId;

  /// the whole message: headers, an empty line and the body. Only ASCII,
  /// every line ends with CRLF.
  final String text;

  List<int> get bytes => ascii.encode(text);
}

/// Turns a [Message] into MIME text.
///
/// - Text and HTML go in `multipart/alternative`.
/// - Inline files (with a cid) go with the HTML in `multipart/related`.
/// - Other files go in `multipart/mixed`.
/// - Text bodies are quoted-printable, files are base64.
/// - Headers that are not ASCII use RFC 2047 encoded words.
class MimeBuilder {
  MimeBuilder({DateTime Function()? clock, Random? random})
    : _clock = clock ?? DateTime.now,
      _random = random ?? Random.secure();

  final DateTime Function() _clock;
  final Random _random;

  /// The MIME text of [message]. The `Bcc` header is left out, unless
  /// [includeBcc] is true (sendmail `-t` reads it, then removes it).
  MimeMessage build(Message message, {bool includeBcc = false}) {
    Address? from = message.from;
    String domain = from == null ? 'localhost' : from.email.split('@').last;

    Map<String, String> headers = <String, String>{};
    String? messageId;
    message.headers.forEach((String name, String value) {
      if (name.toLowerCase() == 'message-id') messageId = value;
    });
    messageId ??= '<${_hex(16)}@$domain>';

    headers['Date'] = MimeEncoding.date(_clock());
    if (from != null) headers['From'] = _addresses(<Address>[from]);
    if (message.to.isNotEmpty) headers['To'] = _addresses(message.to);
    if (message.cc.isNotEmpty) headers['Cc'] = _addresses(message.cc);
    if (includeBcc && message.bcc.isNotEmpty) {
      headers['Bcc'] = _addresses(message.bcc);
    }
    if (message.replyTo.isNotEmpty) {
      headers['Reply-To'] = _addresses(message.replyTo);
    }
    headers['Subject'] = MimeEncoding.encodeWord(message.subject);
    headers['Message-ID'] = messageId!;
    headers['MIME-Version'] = '1.0';
    message.headers.forEach((String name, String value) {
      headers.removeWhere(
        (String key, _) => key.toLowerCase() == name.toLowerCase(),
      );
      headers[name] = MimeEncoding.encodeWord(value);
    });

    _Part root = _body(message);
    StringBuffer out = StringBuffer();
    headers.forEach((String name, String value) {
      out.write(MimeEncoding.header(name, value));
      out.write('\r\n');
    });
    root.write(out);
    return MimeMessage(messageId!, out.toString());
  }

  _Part _body(Message message) {
    _Part? text = message.text == null
        ? null
        : _textPart('text/plain', message.text!);
    _Part? html = message.html == null
        ? null
        : _textPart('text/html', message.html!);
    List<Attachment> inline = <Attachment>[];
    List<Attachment> files = <Attachment>[];
    for (Attachment file in message.attachments) {
      // an inline file needs HTML to show in. Without it, attach it.
      (file.isInline && html != null ? inline : files).add(file);
    }
    if (html != null && inline.isNotEmpty) {
      html = _multi('related', <_Part>[html, ...inline.map(_filePart)]);
    }
    _Part body;
    if (text != null && html != null) {
      body = _multi('alternative', <_Part>[text, html]);
    } else {
      body = (text ?? html)!;
    }
    if (files.isEmpty) return body;
    return _multi('mixed', <_Part>[body, ...files.map(_filePart)]);
  }

  _Part _textPart(String type, String text) {
    return _Part(<String, String>{
      'Content-Type': '$type; charset=utf-8',
      'Content-Transfer-Encoding': 'quoted-printable',
    }, MimeEncoding.quotedPrintable(text));
  }

  _Part _filePart(Attachment file) {
    String disposition = file.isInline ? 'inline' : 'attachment';
    return _Part(<String, String>{
      'Content-Type':
          '${file.contentType}; ${MimeEncoding.fileParam('name', file.filename)}',
      'Content-Transfer-Encoding': 'base64',
      'Content-Disposition':
          '$disposition; ${MimeEncoding.fileParam('filename', file.filename)}',
      if (file.cid != null) 'Content-ID': '<${file.cid}>',
    }, MimeEncoding.base64Lines(file.bytes));
  }

  _Part _multi(String subtype, List<_Part> parts) {
    String boundary = '=_dox_${_hex(12)}';
    return _Part(
      <String, String>{
        'Content-Type': 'multipart/$subtype; boundary="$boundary"',
      },
      null,
      parts: parts,
      boundary: boundary,
    );
  }

  String _addresses(List<Address> list) {
    List<String> items = list
        .map((Address a) => MimeEncoding.address(a.email, a.name))
        .toList();
    String joined = items.join(', ');
    if (joined.length <= 70 && !joined.contains('\r\n')) return joined;
    return items.join(',\r\n ');
  }

  String _hex(int bytes) {
    StringBuffer out = StringBuffer();
    for (int i = 0; i < bytes; i++) {
      out.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return out.toString();
  }
}

class _Part {
  _Part(this.headers, this.body, {this.parts = const <_Part>[], this.boundary});

  final Map<String, String> headers;
  final String? body;
  final List<_Part> parts;
  final String? boundary;

  void write(StringBuffer out) {
    headers.forEach((String name, String value) {
      out.write(MimeEncoding.header(name, value));
      out.write('\r\n');
    });
    out.write('\r\n');
    if (body != null) {
      out.write(body);
      return;
    }
    for (_Part part in parts) {
      out.write('--$boundary\r\n');
      part.write(out);
    }
    out.write('--$boundary--\r\n');
  }
}
