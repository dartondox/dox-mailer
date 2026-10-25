import 'dart:io';
import 'dart:typed_data';

/// A file in an email.
/// ```
/// Attachment(bytes, 'invoice.pdf')
/// Attachment.fromFile('storage/logo.png', cid: 'logo')
/// ```
/// With a [cid], the file is an inline image. Show it in the HTML with
/// `<img src="cid:logo">`.
class Attachment {
  Attachment(List<int> bytes, this.filename, {String? contentType, this.cid})
    : bytes = Uint8List.fromList(bytes),
      contentType = contentType ?? contentTypeOf(filename);

  /// Reads the file at [path]. The file name is the last part of the path.
  factory Attachment.fromFile(
    String path, {
    String? filename,
    String? contentType,
    String? cid,
  }) {
    String name = filename ?? path.split(RegExp(r'[/\\]')).last;
    return Attachment(
      File(path).readAsBytesSync(),
      name,
      contentType: contentType,
      cid: cid,
    );
  }

  final Uint8List bytes;
  final String filename;
  final String contentType;

  /// the content id of an inline file, without `<>` and without `cid:`
  final String? cid;

  bool get isInline => cid != null;

  static const Map<String, String> _types = <String, String>{
    'csv': 'text/csv',
    'gif': 'image/gif',
    'htm': 'text/html',
    'html': 'text/html',
    'ics': 'text/calendar',
    'jpeg': 'image/jpeg',
    'jpg': 'image/jpeg',
    'json': 'application/json',
    'pdf': 'application/pdf',
    'png': 'image/png',
    'svg': 'image/svg+xml',
    'txt': 'text/plain',
    'webp': 'image/webp',
    'xml': 'application/xml',
    'zip': 'application/zip',
  };

  /// A content type from the file extension. Unknown:
  /// `application/octet-stream`.
  static String contentTypeOf(String filename) {
    int dot = filename.lastIndexOf('.');
    if (dot < 0) return 'application/octet-stream';
    String ext = filename.substring(dot + 1).toLowerCase();
    return _types[ext] ?? 'application/octet-stream';
  }
}
