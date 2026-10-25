import 'address.dart';
import 'transport.dart';
import 'transports/log_transport.dart';

/// Settings of the mailers. Put it in `lib/config/mail.dart`.
/// ```
/// MailConfig mailConfig = MailConfig(
///   defaultMailer: Env.get('MAIL_MAILER', 'smtp'),
///   from: Address('hello@example.com', 'My app'),
///   mailers: <String, Transport>{
///     'smtp': SmtpTransport(host: Env.get('MAIL_HOST')),
///     'log': LogTransport(),
///   },
/// );
/// ```
class MailConfig {
  MailConfig({
    this.defaultMailer = 'log',
    Map<String, Transport>? mailers,
    this.from,
    this.replyTo = const <Address>[],
  }) : mailers = mailers ?? <String, Transport>{'log': LogTransport()};

  /// the name of the mailer that `Mail.send()` uses
  final String defaultMailer;

  /// every mailer: a name and its transport
  final Map<String, Transport> mailers;

  /// the from address of a message that has none
  final Address? from;

  /// the reply-to addresses of a message that has none
  final List<Address> replyTo;
}
