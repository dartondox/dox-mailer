import 'dart:io';

import 'package:dox_annotation/install.dart';
import 'package:dox_mailer/commands.dart';
import 'package:test/test.dart';

/// records the `dart` commands, runs nothing
class FakeRunner extends ProcessRunner {
  final List<String> calls = <String>[];

  @override
  Future<int> run(String executable, List<String> args, String folder) async {
    calls.add(args.join(' '));
    return 0;
  }
}

void main() {
  late Directory root;
  late FakeRunner runner;

  void setUpApp() {
    root = Directory.systemTemp.createTempSync('dox_mailer_install_');
    File('${root.path}/pubspec.yaml').writeAsStringSync(
      'name: my_app\n\ndependencies:\n  dox_core: ^3.1.0\n'
      '  dox_builder: ^3.1.0\n',
    );
    File('${root.path}/.env').writeAsStringSync('APP_KEY=x\n');
    runner = FakeRunner();
    exitCode = 0;
  }

  setUp(setUpApp);

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  /// a fresh app folder, in the middle of a test
  Future<void> tearDownAndSetUp() async {
    root.deleteSync(recursive: true);
    setUpApp();
  }

  String read(String path) => File('${root.path}/$path').readAsStringSync();

  Future<void> install(List<String> args) {
    return MailerInstallCommand(root: root, runner: runner).run(args);
  }

  /// every file of the app and its text
  Map<String, String> snapshot() {
    Map<String, String> files = <String, String>{};
    for (FileSystemEntity f in root.listSync(recursive: true)) {
      if (f is File) files[f.path] = f.readAsStringSync();
    }
    return files;
  }

  test('sets up the log transport by default', () async {
    await install(<String>[]);
    expect(exitCode, 0);
    expect(runner.calls, <String>[
      'pub add --dev build_runner',
      'run build_runner build',
    ]);
    expect(
      read('lib/config/mail.dart'),
      allOf(
        contains("Env.get('MAIL_MAILER', 'log')"),
        contains("'log': LogTransport()"),
        isNot(contains('SmtpTransport')),
      ),
    );
    expect(
      read('lib/providers/mail_provider.dart'),
      allOf(
        contains("import 'package:my_app/config/mail.dart';"),
        contains('AppMailProvider extends MailProvider'),
      ),
    );
    expect(
      read('.env'),
      'APP_KEY=x\nMAIL_MAILER=log\nMAIL_FROM=hello@example.com\n',
    );
  });

  test('every transport writes its mailer and its keys', () async {
    Map<String, List<String>> expected = <String, List<String>>{
      'smtp': <String>['SmtpTransport(', 'MAIL_HOST=smtp.example.com'],
      'resend': <String>['ResendTransport(', 'RESEND_API_KEY='],
      'mailgun': <String>['MailgunTransport(', 'MAILGUN_DOMAIN='],
      'postmark': <String>['PostmarkTransport(', 'POSTMARK_TOKEN='],
      'ses': <String>['SesV2Transport(', 'AWS_REGION=us-east-1'],
    };
    for (String transport in expected.keys) {
      await tearDownAndSetUp();
      await install(<String>['--transport=$transport']);
      expect(exitCode, 0, reason: transport);
      expect(
        read('lib/config/mail.dart'),
        allOf(
          contains(expected[transport]![0]),
          contains("'MAIL_MAILER', '$transport'"),
          contains("'log': LogTransport()"),
        ),
        reason: transport,
      );
      expect(read('.env'), contains(expected[transport]![1]));
      expect(read('.env'), contains('MAIL_MAILER=$transport\n'));
    }
  });

  test('--transport with a space works', () async {
    await install(<String>['--transport', 'smtp']);
    expect(read('lib/config/mail.dart'), contains('SmtpTransport('));
  });

  test('the emails folder is made only with dox_view', () async {
    await install(<String>[]);
    expect(Directory('${root.path}/resources').existsSync(), isFalse);
    await tearDownAndSetUp();
    File('${root.path}/pubspec.yaml').writeAsStringSync(
      'name: my_app\ndependencies:\n  dox_core: ^3.1.0\n  dox_view: ^3.1.0\n',
    );
    await install(<String>[]);
    expect(
      Directory('${root.path}/resources/views/emails').existsSync(),
      isTrue,
    );
  });

  test('a second run changes nothing', () async {
    await install(<String>['--transport=smtp']);
    File('${root.path}/lib/config/mail.dart').writeAsStringSync('mine');
    Map<String, String> before = snapshot();
    await install(<String>['--transport=smtp']);
    expect(snapshot(), before);
  });

  test('a bad option stops with exit code 1 and writes nothing', () async {
    for (List<String> args in <List<String>>[
      <String>['--transport=pigeon'],
      <String>['--transpor=smtp'],
      <String>['--transport'],
      <String>['--transport='],
      <String>['smtp'],
    ]) {
      Map<String, String> before = snapshot();
      await install(args);
      expect(exitCode, 1, reason: '$args');
      expect(runner.calls, isEmpty, reason: '$args');
      expect(snapshot(), before, reason: '$args');
      exitCode = 0;
    }
  });

  test('existing .env keys and comments stay the same', () async {
    String env = '# mine\nMAIL_FROM=me@mine.dev # keep\nAPP_KEY=x\n';
    File('${root.path}/.env').writeAsStringSync(env);
    await install(<String>[]);
    expect(read('.env'), startsWith(env));
    expect(read('.env'), isNot(contains('hello@example.com')));
  });
}
