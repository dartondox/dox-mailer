import '../address.dart';
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

  /// Checks that a message was sent. With [test], a message that
  /// [test] says yes to. Throws a [StateError] when there is none.
  /// ```
  /// mail.assertSent((Message m) => m.subject == 'Welcome');
  /// ```
  void assertSent([bool Function(Message message)? test]) {
    if (_count(messages, test) == 0) {
      throw StateError(_text('No matching email was sent', messages));
    }
  }

  /// Checks that [count] messages were sent. With [test], [count]
  /// messages that [test] says yes to.
  void assertSentCount(int count, [bool Function(Message message)? test]) {
    int found = _count(messages, test);
    if (found != count) {
      throw StateError(
        _text(
          'Expected $count sent ${count == 1 ? 'email' : 'emails'}, '
          'found $found',
          messages,
        ),
      );
    }
  }

  /// Checks that no message that [test] says yes to was sent.
  void assertNotSent(bool Function(Message message) test) {
    int found = _count(messages, test);
    if (found > 0) {
      throw StateError(
        _text('Expected no matching sent email, found $found', messages),
      );
    }
  }

  /// Checks that no message was sent.
  void assertNothingSent() {
    if (sent.isNotEmpty) {
      throw StateError(_text('No email should be sent', messages));
    }
  }

  /// Like [assertSent], for the [queued] messages.
  void assertQueued([bool Function(Message message)? test]) {
    if (_count(_queuedMessages, test) == 0) {
      throw StateError(_text('No matching email was queued', _queuedMessages));
    }
  }

  /// Like [assertNotSent], for the [queued] messages.
  void assertNotQueued(bool Function(Message message) test) {
    int found = _count(_queuedMessages, test);
    if (found > 0) {
      throw StateError(
        _text(
          'Expected no matching queued email, found $found',
          _queuedMessages,
        ),
      );
    }
  }

  /// Checks that no message was queued.
  void assertNothingQueued() {
    if (queued.isNotEmpty) {
      throw StateError(_text('No email should be queued', _queuedMessages));
    }
  }

  List<Message> get _queuedMessages =>
      queued.map((QueuedMessage q) => q.message).toList();

  int _count(List<Message> list, bool Function(Message message)? test) {
    return test == null ? list.length : list.where(test).length;
  }

  /// [problem], then the subject and the to addresses of each message
  String _text(String problem, List<Message> list) {
    if (list.isEmpty) return '$problem. There are no emails.';
    StringBuffer out = StringBuffer('$problem. The emails:');
    for (Message m in list) {
      String to = m.to.map((Address a) => a.email).join(', ');
      out.write('\n- "${m.subject}" to $to');
    }
    return out.toString();
  }

  /// forget the sent and the queued messages
  void clear() {
    sent.clear();
    queued.clear();
  }
}
