import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

class _Broken extends Transport {
  int calls = 0;

  @override
  Future<SentMessage> deliver(Message message) async {
    calls++;
    throw MailException('down');
  }
}

/// A transport written the way 3.0.0 asked: it sets send(), not deliver().
class _Old extends Transport {
  _Old([this.error]);

  final Object? error;
  final List<Message> sent = <Message>[];

  @override
  Future<SentMessage> send(Message message) async {
    if (error != null) throw error!;
    sent.add(message);
    return SentMessage(message, messageId: 'old-${sent.length}');
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

  test('a direct transport send checks the message', () async {
    ArrayTransport array = ArrayTransport();
    await expectLater(
      array.send(_message()), // no from address
      throwsA(isA<MailException>()),
    );
    expect(array.sent, isEmpty);
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

  test('a transport that sets send() still works', () async {
    _Old old = _Old();
    Mailer mailer = Mailer('old', old, from: const Address('app@example.com'));
    SentMessage sent = await mailer.send(_message());
    expect(sent.messageId, 'old-1');
    expect(old.sent.single.from, const Address('app@example.com'));
    // Mailer.send still checks the message for it
    await expectLater(
      mailer.send(
        Message(to: <Address>[const Address('not an email')], text: 'x'),
      ),
      throwsA(isA<MailException>()),
    );
    expect(old.sent, hasLength(1));
  });

  test('FailoverTransport throws the last error, as 3.0.0 did', () async {
    _Old first = _Old(Exception('first'));
    StateError last = StateError('last');
    List<Object> seen = <Object>[];
    FailoverTransport failover = FailoverTransport(
      <Transport>[first, _Old(last)],
      onError: (Transport transport, Object error, StackTrace stack) {
        seen.add(error);
      },
    );
    await expectLater(
      failover.send(_message(from: const Address('a@example.com'))),
      throwsA(same(last)),
    );
    expect(seen, hasLength(2));
    expect(seen.last, same(last));
  });

  test('FailoverTransport does not try a bad message', () async {
    _Broken broken = _Broken();
    ArrayTransport backup = ArrayTransport();
    FailoverTransport failover = FailoverTransport(<Transport>[broken, backup]);
    Message bad = Message(
      from: const Address('a@example.com'),
      to: <Address>[const Address('not an email')],
      text: 'x',
    );
    await expectLater(failover.send(bad), throwsA(isA<MailException>()));
    expect(broken.calls, 0);
    expect(backup.sent, isEmpty);
  });

  test('MailProvider sets up Mail and closes the transports', () async {
    _Closable transport = _Closable();
    MailProvider service = MailProvider(
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
