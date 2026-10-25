import '../message.dart';
import '../transport.dart';

/// Tries each transport in order, until one sends the message. Throws
/// the error of the last one when none can.
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
  Future<SentMessage> send(Message message) async {
    for (int i = 0; i < transports.length; i++) {
      try {
        return await transports[i].send(message);
      } catch (_) {
        if (i == transports.length - 1) rethrow;
      }
    }
    throw StateError('unreachable');
  }

  @override
  Future<void> close() async {
    for (Transport transport in transports) {
      await transport.close();
    }
  }
}
