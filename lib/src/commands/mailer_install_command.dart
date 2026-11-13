import 'dart:io';

import 'package:dox_annotation/command.dart';
import 'package:dox_annotation/install.dart';

/// `dox mailer:install [--transport=log|smtp|resend|mailgun|postmark|ses]`.
/// `dox add mailer` runs it. It sets up mail in an app: the mail config,
/// the provider, the `MAIL_*` keys of the transport, and a
/// `resources/views/emails` folder when the app uses dox_view.
/// It never overwrites a file, so it is safe to run twice.
class MailerInstallCommand extends Command {
  /// [root] is the app folder (the current folder by default). [runner]
  /// runs `dart`, tests pass a fake one.
  MailerInstallCommand({this.root, this.runner});

  final Directory? root;
  final ProcessRunner? runner;

  static const List<String> transports = <String>[
    'log',
    'smtp',
    'resend',
    'mailgun',
    'postmark',
    'ses',
  ];

  @override
  String get name => 'mailer:install';

  @override
  String get description => 'Set up sending email in this app';

  @override
  String get usage =>
      'mailer:install [--transport=log|smtp|resend|mailgun|postmark|ses]';

  @override
  Future<void> run(List<String> args) async {
    String? transport = _transport(args);
    if (transport == null) {
      print(
        'Unknown option. Use --transport=log, smtp, resend, mailgun, '
        'postmark or ses (log when not given).',
      );
      exitCode = 1;
      return;
    }
    Installer installer = Installer(root: root, runner: runner);

    await installer.addDependency('dox_core');
    await installer.addDependency('dox_builder', dev: true);
    await installer.addDependency('build_runner', dev: true);

    installer.writeFile('lib/config/mail.dart', mailConfig(transport));
    installer.writeFile(
      'lib/providers/mail_provider.dart',
      mailProvider(installer.appName),
    );

    Map<String, String> keys = envKeys(transport);
    for (String key in keys.keys) {
      installer.addEnv(key, keys[key]!);
    }

    if (installer.hasDependency('dox_view')) {
      installer.makeFolder('resources/views/emails');
    } else {
      installer.note(
        'skipped  resources/views/emails (the app has no dox_view)',
      );
    }

    await installer.buildRunner();
    installer.printSummary(<String>[
      if (transport != 'log')
        'Fill in the $transport keys in .env. Set MAIL_MAILER=log to print '
            'emails instead of sending them.',
      'Send one: `await Mail.send(Message(to: <Address>[Address(...)], '
          "subject: 'Hi', text: 'Hello'));`",
    ]);
  }

  /// the value of `--transport=x` or `--transport x`, log when not given.
  /// Null for an unknown option, a missing value or an unknown transport.
  String? _transport(List<String> args) {
    String transport = 'log';
    for (int i = 0; i < args.length; i++) {
      if (args[i].startsWith('--transport=')) {
        transport = args[i].substring('--transport='.length);
      } else if (args[i] == '--transport' && i + 1 < args.length) {
        transport = args[++i];
      } else {
        return null;
      }
    }
    return transports.contains(transport) ? transport : null;
  }

  /// the `.env` keys of [transport]
  static Map<String, String> envKeys(String transport) {
    return <String, String>{
      'MAIL_MAILER': transport,
      'MAIL_FROM': 'hello@example.com',
      ...switch (transport) {
        'smtp' => <String, String>{
          'MAIL_HOST': 'smtp.example.com',
          'MAIL_PORT': '587',
          'MAIL_USERNAME': '',
          'MAIL_PASSWORD': '',
        },
        'resend' => <String, String>{'RESEND_API_KEY': ''},
        'mailgun' => <String, String>{
          'MAILGUN_API_KEY': '',
          'MAILGUN_DOMAIN': '',
        },
        'postmark' => <String, String>{'POSTMARK_TOKEN': ''},
        'ses' => <String, String>{
          'AWS_ACCESS_KEY_ID': '',
          'AWS_SECRET_ACCESS_KEY': '',
          'AWS_REGION': 'us-east-1',
        },
        _ => <String, String>{},
      },
    };
  }

  /// the `mailers` entry of [transport], without the `log` one
  static String _mailer(String transport) {
    return switch (transport) {
      'smtp' =>
        '''
    'smtp': SmtpTransport(
      host: Env.get('MAIL_HOST', 'localhost'),
      port: Env.get<int>('MAIL_PORT', 587),
      username: Env.get<String?>('MAIL_USERNAME'),
      password: Env.get<String?>('MAIL_PASSWORD'),
    ),
''',
      'resend' =>
        '''
    'resend': ResendTransport(apiKey: Env.get('RESEND_API_KEY', '')),
''',
      'mailgun' =>
        '''
    'mailgun': MailgunTransport(
      apiKey: Env.get('MAILGUN_API_KEY', ''),
      domain: Env.get('MAILGUN_DOMAIN', ''),
    ),
''',
      'postmark' =>
        '''
    'postmark': PostmarkTransport(serverToken: Env.get('POSTMARK_TOKEN', '')),
''',
      'ses' =>
        '''
    'ses': SesV2Transport(
      key: Env.get('AWS_ACCESS_KEY_ID', ''),
      secret: Env.get('AWS_SECRET_ACCESS_KEY', ''),
      region: Env.get('AWS_REGION', 'us-east-1'),
    ),
''',
      _ => '',
    };
  }

  /// `lib/config/mail.dart` for [transport]
  static String mailConfig(String transport) {
    return '''
import 'package:dox_core/dox_core.dart';
import 'package:dox_mailer/dox_mailer.dart';

/// Mail settings
/// -------------------------------
/// `defaultMailer`: the mailer that `Mail.send()` uses. It is a key of
/// `mailers`. Set `MAIL_MAILER` in .env to change it.
/// `from`: the from address of a message that has none.
/// `mailers`: each mailer name and its transport. `log` prints emails
/// and sends nothing.
MailConfig mailConfig = MailConfig(
  defaultMailer: Env.get('MAIL_MAILER', '$transport'),
  from: Address(Env.get('MAIL_FROM', 'hello@example.com'), 'My app'),
  mailers: <String, Transport>{
${_mailer(transport)}    'log': LogTransport(),
  },
);
''';
  }

  /// `lib/providers/mail_provider.dart`
  static String mailProvider(String app) {
    return '''
import 'package:dox_mailer/dox_mailer.dart';
import 'package:$app/config/mail.dart';

/// Mail provider
/// --------------------------
/// Sets up the mailers in every isolate, and closes the SMTP and HTTP
/// clients when the server stops.
/// (Dox finds every DoxProvider class, see lib/generated/container.g.dart).
class AppMailProvider extends MailProvider {
  AppMailProvider() : super(mailConfig);
}
''';
  }
}
