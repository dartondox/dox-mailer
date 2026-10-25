import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

class _Broken extends Transport {
  int calls = 0;

  @override
  Future<SentMessage> send(Message message) async {
    calls++;
    throw MailException('down');
  }
}

class _Closable extends ArrayTransport {
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
  }
}

Message _message({Address? from}) => Message(
  from: from,
  to: <Address>[const Address('ann@example.com')],
  subject: 'Hi',
  text: 'Hello',
);

void main() {
  late ArrayTransport main;
  late ArrayTransport other;

  setUp(() {
    Mail.restore();
    main = ArrayTransport();
    other = ArrayTransport();
    Mail.configure(
      MailConfig(
        defaultMailer: 'main',
        from: const Address('app@example.com', 'App'),
        replyTo: <Address>[const Address('help@example.com')],
        mailers: <String, Transport>{'main': main, 'other': other},
      ),
    );
  });

  test('Mail.send uses the default mailer and the default from', () async {
    SentMessage sent = await Mail.send(_message());
    expect(main.sent, hasLength(1));
    expect(other.sent, isEmpty);
    expect(sent.message.from, const Address('app@example.com', 'App'));
    expect(sent.message.replyTo, <Address>[const Address('help@example.com')]);
  });

  test('a from address of the message wins', () async {
    await Mail.send(_message(from: const Address('me@example.com')));
    expect(main.messages.single.from, const Address('me@example.com'));
  });

  test('Mail.mailer picks a named mailer', () async {
    await Mail.mailer('other').send(_message());
    expect(other.sent, hasLength(1));
    expect(main.sent, isEmpty);
    expect(Mail.mailer('other').name, 'other');
  });

  test('an unknown mailer is an ArgumentError', () {
    expect(() => Mail.mailer('nope'), throwsArgumentError);
  });

  test('a message with no recipient is not sent', () async {
    await expectLater(
      Mail.send(Message(subject: 'x', text: 'x')),
      throwsA(isA<MailException>()),
    );
    expect(main.sent, isEmpty);
  });

  test('Mail.fake catches every mailer', () async {
    ArrayTransport fake = Mail.fake();
    await Mail.send(_message());
    await Mail.mailer('other').send(_message());
    expect(fake.sent, hasLength(2));
    expect(main.sent, isEmpty);
    Mail.restore();
    await Mail.send(_message());
    expect(fake.sent, hasLength(2));
    expect(main.sent, hasLength(1));
  });

  test('LogTransport prints the message', () async {
    List<String> lines = <String>[];
    LogTransport log = LogTransport(output: lines.add);
    await log.send(
      Message(
        from: const Address('app@example.com'),
        to: <Address>[const Address('ann@example.com', 'Ann')],
        subject: 'Hi',
        text: 'Hello Ann',
      ),
    );
    expect(lines.single, contains('To: Ann <ann@example.com>'));
    expect(lines.single, contains('Subject: Hi'));
    expect(lines.single, contains('Hello Ann'));
  });

  test('FailoverTransport tries the next one', () async {
    _Broken broken = _Broken();
    ArrayTransport backup = ArrayTransport();
    FailoverTransport failover = FailoverTransport(<Transport>[broken, backup]);
    await failover.send(_message(from: const Address('a@example.com')));
    expect(broken.calls, 1);
    expect(backup.sent, hasLength(1));

    FailoverTransport allDown = FailoverTransport(<Transport>[
      _Broken(),
      _Broken(),
    ]);
    await expectLater(
      allDown.send(_message(from: const Address('a@example.com'))),
      throwsA(isA<MailException>()),
    );
  });

  test('MailService sets up Mail and closes the transports', () async {
    _Closable transport = _Closable();
    MailService service = MailService(
      MailConfig(
        defaultMailer: 'x',
        from: const Address('app@example.com'),
        mailers: <String, Transport>{'x': transport},
      ),
    );
    service.setup();
    await Mail.send(_message());
    expect(transport.sent, hasLength(1));
    await service.shutdown();
    expect(transport.closed, isTrue);
  });
}
