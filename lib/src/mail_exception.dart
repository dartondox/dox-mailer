/// Thrown when an email can not be sent: a bad message, a server that
/// says no, or an API that returns an error.
class MailException implements Exception {
  MailException(this.message, {this.statusCode, this.body});

  final String message;

  /// the HTTP status or the SMTP reply code, when there is one
  final int? statusCode;

  /// the answer of the server, when there is one
  final String? body;

  @override
  String toString() => 'MailException: $message';
}
