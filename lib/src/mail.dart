import 'mail_config.dart';
import 'mail_queue.dart';
import 'mailer.dart';
import 'message.dart';
import 'transport.dart';
import 'transports/array_transport.dart';

/// Send email.
/// ```
/// await Mail.send(Message(to: [Address('ann@example.com')], ...));
/// await Mail.mailer('ses').send(message);
/// await Mail.queue(message); // a queue worker sends it
/// await Mail.later(Duration(minutes: 5), message);
/// ```
/// `MailProvider` calls [configure] in every isolate.
class Mail {
  Mail._();

  static MailConfig? _config;
  static final Map<String, Mailer> _mailers = <String, Mailer>{};
  static ArrayTransport? _fake;
  static MailQueue? _queue;

  /// Use [config]. Mailers of an old config are not closed.
  static void configure(MailConfig config) {
    _config = config;
    _mailers.clear();
  }

  static MailConfig get config {
    MailConfig? value = _config;
    if (value == null) {
      throw StateError(
        'Mail is not set up. Add a MailProvider to your app, '
        'or call Mail.configure() first',
      );
    }
    return value;
  }

  /// Sends [message] with the default mailer.
  static Future<SentMessage> send(Message message) async {
    return mailer().send(message);
  }

  /// Puts [message] on the job queue. A queue worker sends it later
  /// with the default mailer. Returns the job id. See [Mailer.queue].
  static Future<String> queue(
    Message message, {
    String? queue,
    bool encrypt = false,
  }) {
    return mailer().queue(message, queue: queue, encrypt: encrypt);
  }

  /// Like [queue], but the worker sends it after [delay].
  static Future<String> later(
    Duration delay,
    Message message, {
    String? queue,
    bool encrypt = false,
  }) {
    return mailer().later(delay, message, queue: queue, encrypt: encrypt);
  }

  /// Use [queue] for [Mail.queue] and [Mail.later]. dox_queue calls it
  /// in `Queue.configure()`. Null: no queue.
  static void useQueue(MailQueue? queue) {
    _queue = queue;
  }

  /// the queue of [useQueue]. Throws a [StateError] when there is none.
  static MailQueue get mailQueue {
    MailQueue? value = _queue;
    if (value == null) {
      throw StateError(
        'Mail.queue() needs a job queue. Add the dox_queue package and a '
        'QueueProvider to your app, or call Queue.configure() first',
      );
    }
    return value;
  }

  /// The mailer [name] of the config. Null: the default mailer.
  /// Throws an [ArgumentError] for an unknown name.
  static Mailer mailer([String? name]) {
    MailConfig cfg = config;
    String key = name ?? cfg.defaultMailer;
    return _mailers.putIfAbsent(key, () {
      Transport? transport = _fake ?? cfg.mailers[key];
      if (transport == null) {
        throw ArgumentError.value(
          key,
          'name',
          'is not a mailer. Mailers: ${cfg.mailers.keys.join(', ')}',
        );
      }
      return Mailer(key, transport, from: cfg.from, replyTo: cfg.replyTo);
    });
  }

  /// Every mailer sends to one [ArrayTransport], so a test can check the
  /// sent messages. Sets up an empty config when there is none.
  /// [restore] undoes it.
  /// ```
  /// ArrayTransport mail = Mail.fake();
  /// await signUp('ann@example.com');
  /// expect(mail.sent.single.message.subject, 'Welcome');
  /// ```
  static ArrayTransport fake() {
    _config ??= MailConfig();
    ArrayTransport fake = ArrayTransport();
    _fake = fake;
    _mailers.clear();
    return fake;
  }

  /// Stop the fake: mailers use their own transports again.
  static void restore() {
    _fake = null;
    _mailers.clear();
  }

  /// Close every transport of the config, eg. open SMTP connections.
  static Future<void> close() async {
    MailConfig? cfg = _config;
    if (cfg == null) return;
    for (Transport transport in cfg.mailers.values) {
      await transport.close();
    }
  }
}
