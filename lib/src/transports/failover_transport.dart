import '../header_check.dart';
import '../message.dart';
import '../transport.dart';

/// Tries each transport in order, until one sends the message. Throws
/// the error of the last one when none can.
///
/// [onError] gets the error of each transport that fails, so you can see
/// why the first ones failed too. When [onError] throws, that error is
/// ignored and the next transport is still tried.
///
/// A bad address or a header line break throws a `MailException` at
/// once. It is checked before the first transport, so no transport tries
/// it.
/// ```
/// 'main': FailoverTransport(<Transport>[ses, smtp]),
/// ```
class FailoverTransport extends Transport {
  FailoverTransport(this.transports, {this.onError}) {
    if (transports.isEmpty) {
      throw ArgumentError.value(transports, 'transports', 'is empty');
    }
  }

  final List<Transport> transports;

  /// Called with the transport, its error and stack trace each time a
  /// transport fails.
  final void Function(Transport transport, Object error, StackTrace stack)?
  onError;

  @override
  Future<SentMessage> send(Message message) async {
    checkHeaders(message);
    for (int i = 0; i < transports.length; i++) {
      try {
        return await transports[i].send(message);
      } catch (error, stack) {
        _report(transports[i], error, stack);
        if (i == transports.length - 1) rethrow;
      }
    }
    throw StateError('unreachable');
  }

  /// Calls [onError]. An error thrown by [onError] is ignored, so the
  /// next transport is still tried and the send error is not lost.
  void _report(Transport transport, Object error, StackTrace stack) {
    try {
      onError?.call(transport, error, stack);
    } catch (_) {
      // ponytail: dropped, add a hook for it if someone needs to see it
    }
  }

  @override
  Future<void> close() async {
    for (Transport transport in transports) {
      await transport.close();
    }
  }
}
