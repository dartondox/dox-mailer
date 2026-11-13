import 'message.dart';

/// Puts a mail on a job queue, for `Mail.queue()` and `Mail.later()`.
///
/// The default is [QueueMailQueue]: the mails are jobs of dox_queue, so
/// the app needs a `QueueProvider`. A test can set its own with
/// `Mail.useQueue()`.
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
