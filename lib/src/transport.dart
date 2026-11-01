import 'message.dart';

/// Sends a [Message]. There is one transport class per provider.
///
/// A new transport sets [deliver]. Then [send] checks the message first.
/// A transport that sets [send] itself (the 3.0.0 way) still works.
/// `Mail.send` checks its messages, but a direct call to its [send] does
/// not.
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
  ///
  /// It has a body, so a transport that only sets [send] still compiles.
  Future<SentMessage> deliver(Message message) {
    throw UnimplementedError('$runtimeType must set send() or deliver()');
  }

  /// Close open connections and HTTP clients. The default does nothing.
  Future<void> close() async {}
}
