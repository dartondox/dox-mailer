import 'message.dart';

/// Sends a [Message]. There is one transport class per provider.
///
/// A transport sets [deliver]. Call [send]: it checks the message first.
abstract class Transport {
  /// Checks [message] with `Message.check`, then sends it with [deliver].
  /// Throws a `MailException` when the message is not complete or has a
  /// bad address, header or attachment.
  Future<SentMessage> send(Message message) async {
    // every transport checks here, so a direct call can not skip it
    message.check();
    return deliver(message);
  }

  /// Sends [message]. It is already checked and has a from address.
  /// Call [send], not this.
  Future<SentMessage> deliver(Message message);

  /// Close open connections and HTTP clients. The default does nothing.
  Future<void> close() async {}
}
