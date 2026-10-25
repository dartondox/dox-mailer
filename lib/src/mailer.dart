import 'address.dart';
import 'message.dart';
import 'transport.dart';

/// A named transport with the default from address. Get one with
/// `Mail.mailer('ses')`.
class Mailer {
  Mailer(
    this.name,
    this.transport, {
    this.from,
    this.replyTo = const <Address>[],
  });

  final String name;
  final Transport transport;
  final Address? from;
  final List<Address> replyTo;

  /// Sends [message]. A message with no from (or reply-to) address gets
  /// the one of the config. Throws a `MailException` when the message is
  /// not complete or the provider says no.
  Future<SentMessage> send(Message message) async {
    Message full = message.copyWith(
      from: message.from ?? from,
      replyTo: message.replyTo.isEmpty ? replyTo : null,
    );
    full.check();
    return transport.send(full);
  }
}
