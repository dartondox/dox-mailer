import 'message.dart';

/// Puts a mail on a job queue, for `Mail.queue()` and `Mail.later()`.
///
/// dox_mailer has no queue of its own. The dox_queue package sets one
/// in `Queue.configure()`, so add dox_queue and its `QueueProvider` to
/// the app. A test can set its own with `Mail.useQueue()`.
abstract class MailQueue {
  /// Put [message] on the queue, to be sent later by the mailer
  /// [mailer]. Returns the job id. The worker waits [delay] before it
  /// sends. [queue] is the queue name. Null: the default queue. With
  /// [encrypt], the saved job data is encrypted.
  Future<String> push(
    String mailer,
    Message message, {
    Duration? delay,
    String? queue,
    bool encrypt = false,
  });
}
