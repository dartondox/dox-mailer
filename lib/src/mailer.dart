import 'address.dart';
import 'attachment.dart';
import 'mail.dart';
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
    return sendMessage(transport, await _complete(message));
  }

  /// Puts [message] on the job queue. A queue worker sends it later with
  /// this mailer (the mailer name is saved, so the worker uses the same
  /// transport). Returns the job id.
  ///
  /// The message is checked now, so a bad message fails here and not in
  /// the worker. [queue] is the queue name. Null: `default`. With
  /// [encrypt], the saved job data is encrypted with the app key.
  ///
  /// The whole message is saved in the queue, attachments too (as
  /// base64). Keep attachments small. Needs dox_queue, see [Mail.useQueue].
  Future<String> queue(
    Message message, {
    String? queue,
    bool encrypt = false,
  }) async {
    return Mail.mailQueue.push(
      name,
      await _complete(message),
      queue: queue,
      encrypt: encrypt,
    );
  }

  /// Like [queue], but the worker sends it after [delay].
  Future<String> later(
    Duration delay,
    Message message, {
    String? queue,
    bool encrypt = false,
  }) async {
    return Mail.mailQueue.push(
      name,
      await _complete(message),
      delay: delay,
      queue: queue,
      encrypt: encrypt,
    );
  }

  /// [message] with the default from and reply-to, checked, with the
  /// files of its attachments read
  Future<Message> _complete(Message message) async {
    Message full = message.copyWith(
      from: message.from ?? from,
      replyTo: message.replyTo.isEmpty ? replyTo : null,
    );
    full.check();
    for (Attachment file in full.attachments) {
      await file.load();
    }
    return full;
  }
}
