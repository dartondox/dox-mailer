import '../mail_queue.dart';
import '../message.dart';
import '../transport.dart';
import '../header_check.dart';

/// A message that `Mail.queue()` or `Mail.later()` put on the fake queue.
class QueuedMessage {
  const QueuedMessage(
    this.mailer,
    this.message, {
    required this.id,
    this.delay,
    this.queue,
    this.encrypt = false,
  });

  /// the name of the mailer that would send it
  final String mailer;

  /// the message, with the default from address filled in
  final Message message;

  /// the job id that `Mail.queue()` returned
  final String id;

  /// the wait of `Mail.later()`. Null for `Mail.queue()`.
  final Duration? delay;

  /// the queue name. Null: the default queue.
  final String? queue;
  final bool encrypt;
}

/// Keeps every message in [sent] and sends nothing. For tests.
/// `Mail.fake()` uses it. When it is the fake, it is the job queue too:
/// `Mail.queue()` and `Mail.later()` put the message in [queued].
class ArrayTransport extends Transport implements MailQueue {
  final List<SentMessage> sent = <SentMessage>[];

  /// the messages of `Mail.queue()` and `Mail.later()`, while faked
  final List<QueuedMessage> queued = <QueuedMessage>[];

  /// the sent messages
  List<Message> get messages => sent.map((SentMessage s) => s.message).toList();

  @override
  Future<SentMessage> send(Message message) async {
    checkHeaders(message);
    SentMessage result = SentMessage(
      message,
      messageId: 'array-${sent.length + 1}',
    );
    sent.add(result);
    return result;
  }

  /// Keeps [message] in [queued] and sends nothing.
  @override
  Future<String> push(
    String mailer,
    Message message, {
    Duration? delay,
    String? queue,
    bool encrypt = false,
  }) async {
    checkHeaders(message);
    String id = 'array-job-${queued.length + 1}';
    queued.add(
      QueuedMessage(
        mailer,
        message,
        id: id,
        delay: delay,
        queue: queue,
        encrypt: encrypt,
      ),
    );
    return id;
  }

  /// forget the sent and the queued messages
  void clear() {
    sent.clear();
    queued.clear();
  }
}
