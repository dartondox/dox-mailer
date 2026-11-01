import '../mail_exception.dart';
import '../message.dart';
import '../transport.dart';

/// Tries each transport in order, until one sends the message. Throws a
/// [FailoverException] with the error of each transport when none can.
///
/// A bad message (eg. a bad address) throws a [MailException] at once.
/// It is checked before the first transport, so no transport tries it.
/// ```
/// 'main': FailoverTransport(<Transport>[ses, smtp]),
/// ```
class FailoverTransport extends Transport {
  FailoverTransport(this.transports) {
    if (transports.isEmpty) {
      throw ArgumentError.value(transports, 'transports', 'is empty');
    }
  }

  final List<Transport> transports;

  @override
  Future<SentMessage> deliver(Message message) async {
    List<Object> errors = <Object>[];
    for (Transport transport in transports) {
      try {
        return await transport.send(message);
      } catch (error) {
        errors.add(error);
      }
    }
    throw FailoverException(errors);
  }

  @override
  Future<void> close() async {
    for (Transport transport in transports) {
      await transport.close();
    }
  }
}

/// Thrown by [FailoverTransport] when every transport failed. [errors]
/// has the error of each transport, in order. The status code and body
/// are the ones of the last error.
class FailoverException extends MailException {
  FailoverException(this.errors)
    : super(
        'every transport failed: ${errors.join('; ')}',
        statusCode: _last(errors)?.statusCode,
        body: _last(errors)?.body,
      );

  final List<Object> errors;

  static MailException? _last(List<Object> errors) {
    Object last = errors.last;
    return last is MailException ? last : null;
  }
}
