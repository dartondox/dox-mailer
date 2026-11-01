import 'message.dart';

/// Sends a [Message]. There is one transport class per provider.
///
/// The [Message] is already checked and has a from address when it
/// gets here.
abstract class Transport {
  Future<SentMessage> send(Message message);

  /// Close open connections and HTTP clients. The default does nothing.
  Future<void> close() async {}
}
