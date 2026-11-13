import 'dart:async';
import 'dart:io' show stderr;

import 'address.dart';
import 'mail_config.dart';
import 'mail_queue.dart';
import 'mailable.dart';
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
  static List<Address>? _alwaysTo;
  static final List<FutureOr<void> Function(Message message)> _sending =
      <FutureOr<void> Function(Message message)>[];
  static final List<FutureOr<void> Function(SentMessage sent)> _sent =
      <FutureOr<void> Function(SentMessage sent)>[];

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

  /// Sends a plain text email with the default mailer. [to] is an
  /// [Address], an email text, or a list of these.
  /// ```
  /// await Mail.raw('Hello Ann', to: 'ann@example.com', subject: 'Hi');
  /// ```
  static Future<SentMessage> raw(
    String text, {
    required Object to,
    String subject = '',
  }) {
    return send(Message(to: Address.list(to), subject: subject, text: text));
  }

  /// Start an email to [to]: an [Address], an email text, or a list of
  /// these. Add more with the chained calls of [PendingMail].
  /// ```
  /// await Mail.to('ann@example.com').cc('bob@example.com').send(mail);
  /// await Mail.to(user.email).raw('Hello', subject: 'Hi');
  /// ```
  static PendingMail to(Object to) => PendingMail(Address.list(to));

  /// Send every email to [address] only, eg. on a staging server, so
  /// real users get nothing. The `to` of each email becomes [address]
  /// and `cc` and `bcc` are cleared. It works for queued emails too: it
  /// counts when the worker sends them. [address] is an [Address], an
  /// email text, or a list of these. Null turns it off.
  ///
  /// Each isolate has its own value (server isolates, queue worker). So
  /// call it in `setup()` of your mail provider, after `super.setup()`.
  /// A call in `main()` does not reach queued emails.
  /// ```
  /// class AppMailProvider extends MailProvider {
  ///   AppMailProvider() : super(mailConfig);
  ///
  ///   @override
  ///   void setup() {
  ///     super.setup();
  ///     if (Env.get<String>('APP_ENV') == 'staging') {
  ///       Mail.alwaysTo('qa@example.com');
  ///     }
  ///   }
  /// }
  /// ```
  static void alwaysTo(Object? address) {
    if (address == null) {
      _alwaysTo = null;
      return;
    }
    List<Address> list = Address.list(address);
    for (Address item in list) {
      item.check();
    }
    _alwaysTo = list;
  }

  /// Call [hook] before each email is sent, with the full message (the
  /// default from and [alwaysTo] are set), eg. to log it. When [hook]
  /// throws, the email is not sent and `send()` throws that error.
  ///
  /// Each isolate has its own hooks. Add them in `setup()` of your mail
  /// provider, after `super.setup()`, like [alwaysTo]. A hook added in
  /// `main()` does not run for queued emails. The hooks are kept in a
  /// list, so start `setup()` with [clearHooks]: then a second `setup()`
  /// in the same isolate does not add each hook twice.
  /// ```
  /// Mail.clearHooks();
  /// Mail.onSending((Message message) => print('to ${message.to}'));
  /// ```
  static void onSending(FutureOr<void> Function(Message message) hook) {
    _sending.add(hook);
  }

  /// Call [hook] after each email is sent, eg. to log the message id.
  /// When [hook] throws, the error is logged and `send()` does not
  /// throw: the email is already sent. So a queue worker does not try
  /// the job again and send the email twice. The other hooks still run.
  /// Add it in `setup()` of your mail provider, like [onSending].
  static void onSent(FutureOr<void> Function(SentMessage sent) hook) {
    _sent.add(hook);
  }

  /// Remove the hooks of [onSending] and [onSent], eg. in a test.
  static void clearHooks() {
    _sending.clear();
    _sent.clear();
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

  /// The queue of [useQueue]. While [fake] is on, it is the fake, so
  /// queued messages go to `ArrayTransport.queued`. Throws a
  /// [StateError] when there is none.
  static MailQueue get mailQueue {
    MailQueue? value = _fake ?? _queue;
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
  /// sent messages. [queue] and [later] put the message in its `queued`
  /// list, with no job queue. Sets up an empty config when there is none.
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

/// Sends [message] with [transport], with [Mail.alwaysTo] and the hooks
/// of [Mail.onSending] and [Mail.onSent]. `Mailer.send` uses it. It is
/// not exported.
Future<SentMessage> sendMessage(Transport transport, Message message) async {
  List<Address>? alwaysTo = Mail._alwaysTo;
  if (alwaysTo != null) {
    message = message.copyWith(
      to: alwaysTo,
      cc: const <Address>[],
      bcc: const <Address>[],
    );
  }
  for (FutureOr<void> Function(Message message) hook in Mail._sending) {
    await hook(message);
  }
  SentMessage sent = await transport.send(message);
  // The email is sent. A hook error must not fail the send: a queue
  // worker would try the job again and send the email twice.
  for (FutureOr<void> Function(SentMessage sent) hook in Mail._sent) {
    try {
      await hook(sent);
    } catch (error, stack) {
      _logSentHookError(error, stack);
    }
  }
  return sent;
}

void _logSentHookError(Object error, StackTrace stack) {
  String text = 'Mail: an onSent hook threw. The email was sent: $error';
  try {
    stderr.writeln('$text\n$stack');
  } catch (_) {
    // a closed stderr must not make `send()` fail after the email was sent
  }
}

/// An email that is being built with chained calls. Get one with
/// [Mail.to].
/// ```
/// await Mail.to('ann@example.com')
///     .cc('bob@example.com')
///     .bcc(<String>['audit@example.com'])
///     .send(WelcomeMail(user));
/// ```
class PendingMail {
  PendingMail(this._to);

  final List<Address> _to;
  final List<Address> _cc = <Address>[];
  final List<Address> _bcc = <Address>[];

  /// add cc recipients: an [Address], an email text, or a list of these
  PendingMail cc(Object address) {
    _cc.addAll(Address.list(address));
    return this;
  }

  /// add bcc recipients: an [Address], an email text, or a list of these
  PendingMail bcc(Object address) {
    _bcc.addAll(Address.list(address));
    return this;
  }

  /// Sends [mail] with its mailer. The recipients of this builder are
  /// added to the ones of [mail].
  Future<SentMessage> send(Mailable mail) {
    return Mail.mailer(mail.mailer).send(_message(mail.toMessage()));
  }

  /// Puts [mail] on the job queue, see [Mail.queue].
  Future<String> queue(Mailable mail, {String? queue, bool encrypt = false}) {
    return Mail.mailer(mail.mailer)
        .queue(_message(mail.toMessage()), queue: queue, encrypt: encrypt);
  }

  /// Like [queue], but the worker sends it after [delay].
  Future<String> later(
    Duration delay,
    Mailable mail, {
    String? queue,
    bool encrypt = false,
  }) {
    return Mail.mailer(
      mail.mailer,
    ).later(delay, _message(mail.toMessage()), queue: queue, encrypt: encrypt);
  }

  /// Sends a plain text email with the default mailer.
  Future<SentMessage> raw(String text, {String subject = ''}) {
    return Mail.send(_message(Message(subject: subject, text: text)));
  }

  Message _message(Message message) {
    return message.copyWith(
      to: <Address>[...message.to, ..._to],
      cc: <Address>[...message.cc, ..._cc],
      bcc: <Address>[...message.bcc, ..._bcc],
    );
  }
}
