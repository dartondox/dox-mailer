import 'mail_config.dart';
import 'mailer.dart';
import 'message.dart';
import 'transport.dart';
import 'transports/array_transport.dart';

/// Send email.
/// ```
/// await Mail.send(Message(to: [Address('ann@example.com')], ...));
/// await Mail.mailer('ses').send(message);
/// ```
/// `MailService` calls [configure] in every isolate.
class Mail {
  Mail._();

  static MailConfig? _config;
  static final Map<String, Mailer> _mailers = <String, Mailer>{};
  static ArrayTransport? _fake;

  /// Use [config]. Mailers of an old config are not closed.
  static void configure(MailConfig config) {
    _config = config;
    _mailers.clear();
  }

  static MailConfig get config {
    MailConfig? value = _config;
    if (value == null) {
      throw StateError(
        'Mail is not set up. Add a MailService to your app, '
        'or call Mail.configure() first',
      );
    }
    return value;
  }

  /// Sends [message] with the default mailer.
  static Future<SentMessage> send(Message message) async {
    return mailer().send(message);
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
