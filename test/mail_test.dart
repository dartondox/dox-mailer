import 'dart:io';

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

/// A transport written the way 3.0.0 asked: it extends Transport and sets send().
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

/// A transport that implements Transport, the way 3.0.0 allowed.
class _Implements implements Transport {
  final List<Message> sent = <Message>[];

  @override
  Future<SentMessage> send(Message message) async {
    sent.add(message);
    return SentMessage(message, messageId: 'impl-${sent.length}');
  }

  @override
  Future<void> close() async {}
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
  fakeAssertTests();

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

  test('Attachment.fromFile reads the file when the message is sent', () async {
    Directory dir = await Directory.systemTemp.createTemp('dox_mailer_');
    addTearDown(() => dir.delete(recursive: true));
    String path = '${dir.path}/terms.pdf';
    // no file yet: fromFile does not read it
    Attachment file = Attachment.fromFile(path);
    expect(file.filename, 'terms.pdf');
    expect(file.contentType, 'application/pdf');
    Message message = _message().copyWith(attachments: <Attachment>[file]);
    await expectLater(Mail.send(message), throwsA(isA<FileSystemException>()));

    await File(path).writeAsBytes(<int>[1, 2, 3]);
    await Mail.send(message);
    expect(main.messages.single.attachments.single.bytes, <int>[1, 2, 3]);
    // read without send too
    expect(Attachment.fromFile(path).bytes, <int>[1, 2, 3]);
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

  test('a direct transport send stops header injection', () async {
    ArrayTransport array = ArrayTransport();
    await expectLater(
      array.send(_message(from: const Address('a@example.com\r\nBcc: x@y.z'))),
      throwsA(isA<MailException>()),
    );
    expect(array.sent, isEmpty);
  });

  test('a direct transport send takes a message with no from', () async {
    // as in 3.0.0: only Mailer.send asks for a from, recipient and body
    ArrayTransport array = ArrayTransport();
    await array.send(Message(to: <Address>[const Address('a@example.com')]));
    expect(array.sent, hasLength(1));
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

  test('a class that implements Transport still works', () async {
    _Implements impl = _Implements();
    Mailer mailer = Mailer('impl', impl, from: const Address('a@example.com'));
    SentMessage sent = await mailer.send(_message());
    expect(sent.messageId, 'impl-1');
    FailoverTransport failover = FailoverTransport(<Transport>[
      _Broken(),
      impl,
    ]);
    await failover.send(_message(from: const Address('a@example.com')));
    expect(impl.sent, hasLength(2));
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

  test('a direct failover send takes a message with no from', () async {
    // as in 3.0.0: only Mailer.send asks for a from, recipient and body
    ArrayTransport backup = ArrayTransport();
    FailoverTransport failover = FailoverTransport(<Transport>[
      _Broken(),
      backup,
    ]);
    await failover.send(Message(to: <Address>[const Address('a@example.com')]));
    expect(backup.sent, hasLength(1));
  });

  test('a direct send takes addresses that 3.0.0 took', () async {
    // only a CR or LF is rejected here; Mailer.send does the full check
    for (Address odd in <Address>[
      const Address('root'),
      const Address('ann lee@example.com'),
      const Address('a<b>,c;d@example.com'),
    ]) {
      Message message = Message(from: odd, to: <Address>[odd], text: 'x');
      ArrayTransport array = ArrayTransport();
      await array.send(message);
      expect(array.sent, hasLength(1));
      ArrayTransport backup = ArrayTransport();
      await FailoverTransport(<Transport>[_Broken(), backup]).send(message);
      expect(backup.sent, hasLength(1));
      await expectLater(
        Mailer('x', ArrayTransport()).send(message),
        throwsA(isA<MailException>()),
      );
    }
    Message crlf = Message(
      to: <Address>[const Address('root\r\nBcc: x@y.z')],
      text: 'x',
    );
    await expectLater(
      ArrayTransport().send(crlf),
      throwsA(isA<MailException>()),
    );
    await expectLater(
      FailoverTransport(<Transport>[ArrayTransport()]).send(crlf),
      throwsA(isA<MailException>()),
    );
  });

  test('FailoverTransport does not try a bad message', () async {
    _Broken broken = _Broken();
    ArrayTransport backup = ArrayTransport();
    FailoverTransport failover = FailoverTransport(<Transport>[broken, backup]);
    Message bad = Message(
      from: const Address('a@example.com'),
      to: <Address>[const Address('ann@example.com\r\nBcc: x@y.z')],
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

void _fails(void Function() check, Object text) {
  expect(
    check,
    throwsA(
      isA<StateError>().having((StateError e) => e.message, 'message', text),
    ),
  );
}

bool _isHi(Message m) => m.subject == 'Hi';
bool _isBye(Message m) => m.subject == 'Bye';

void fakeAssertTests() {
  group('ArrayTransport asserts', () {
    late ArrayTransport mail;

    setUp(() {
      Mail.configure(MailConfig(from: const Address('app@example.com')));
      mail = Mail.fake();
    });

    tearDown(Mail.restore);

    test('with nothing sent or queued', () {
      mail.assertNothingSent();
      mail.assertNothingQueued();
      mail.assertSentCount(0);
      mail.assertNotSent(_isHi);
      mail.assertNotQueued(_isHi);
      _fails(
        mail.assertSent,
        'No matching email was sent. There are no emails.',
      );
      _fails(mail.assertQueued, startsWith('No matching email was queued'));
    });

    test('sent mail', () async {
      await Mail.send(_message());
      await Mail.send(_message());
      mail.assertSent();
      mail.assertSent(_isHi);
      mail.assertSentCount(2);
      mail.assertSentCount(2, _isHi);
      mail.assertSentCount(0, _isBye);
      mail.assertNotSent(_isBye);
      mail.assertNothingQueued();
      _fails(
        () => mail.assertSent(_isBye),
        'No matching email was sent. The emails:\n'
        '- "Hi" to ann@example.com\n'
        '- "Hi" to ann@example.com',
      );
      _fails(
        () => mail.assertSentCount(1),
        startsWith('Expected 1 sent emails, found 2'),
      );
      _fails(
        () => mail.assertNotSent(_isHi),
        startsWith('Expected no matching sent email, found 2'),
      );
      _fails(mail.assertNothingSent, startsWith('No email should be sent'));
    });

    test('queued mail', () async {
      await Mail.queue(_message());
      await Mail.later(const Duration(minutes: 1), _message());
      mail.assertQueued();
      mail.assertQueued(_isHi);
      mail.assertNotQueued(_isBye);
      mail.assertNothingSent();
      _fails(
        () => mail.assertQueued(_isBye),
        contains('"Hi" to ann@example.com'),
      );
      _fails(
        () => mail.assertNotQueued(_isHi),
        startsWith('Expected no matching queued email, found 2'),
      );
      _fails(mail.assertNothingQueued, startsWith('No email should be queued'));
      mail.clear();
      mail.assertNothingQueued();
    });
  });
}
