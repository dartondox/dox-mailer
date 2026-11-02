import 'dart:convert';

import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

/// One call of [_FakeQueue.push].
class _Push {
  _Push(this.mailer, this.json, this.delay, this.queue, this.encrypt);

  final String mailer;

  /// the message as JSON text, like a real queue saves it
  final String json;
  final Duration? delay;
  final String? queue;
  final bool encrypt;
}

/// Keeps each push. [work] sends them, like a queue worker.
class _FakeQueue implements MailQueue {
  final List<_Push> pushed = <_Push>[];

  @override
  Future<String> push(
    String mailer,
    Message message, {
    Duration? delay,
    String? queue,
    bool encrypt = false,
  }) async {
    String json = jsonEncode(message.toJson());
    pushed.add(_Push(mailer, json, delay, queue, encrypt));
    return 'job-${pushed.length}';
  }

  Future<void> work() async {
    for (_Push push in pushed) {
      Map<String, Object?> data = jsonDecode(push.json) as Map<String, Object?>;
      await Mail.mailer(push.mailer).send(Message.fromJson(data));
    }
  }
}

Message _full() => Message(
  from: const Address('me@example.com', 'Me "Boss"'),
  to: <Address>[const Address('ann@example.com', 'Ann Lee')],
  cc: <Address>[const Address('bob@example.com')],
  bcc: <Address>[const Address('eve@example.com')],
  replyTo: <Address>[const Address('help@example.com')],
  subject: 'Your invoice',
  text: 'Hi Ann',
  html: '<p>Hi Ann</p>',
  attachments: <Attachment>[
    Attachment(<int>[0, 1, 2, 255, 128], 'invoice.pdf'),
    Attachment(<int>[9, 8], 'logo', contentType: 'image/png', cid: 'logo'),
  ],
  headers: <String, String>{'X-Campaign': 'fall'},
  tags: <String>['billing'],
  metadata: <String, String>{'user_id': '42'},
);

void main() {
  late ArrayTransport main;
  late ArrayTransport other;
  late _FakeQueue queue;

  setUp(() {
    Mail.restore();
    main = ArrayTransport();
    other = ArrayTransport();
    queue = _FakeQueue();
    Mail.configure(
      MailConfig(
        defaultMailer: 'main',
        from: const Address('app@example.com', 'App'),
        mailers: <String, Transport>{'main': main, 'other': other},
      ),
    );
    Mail.useQueue(queue);
  });

  tearDown(() {
    Mail.restore();
    Mail.useQueue(null);
  });

  test('a message is the same after toJson, JSON text and fromJson', () {
    Message message = _full();
    Message back = Message.fromJson(
      jsonDecode(jsonEncode(message.toJson())) as Map<String, Object?>,
    );
    expect(back.from, message.from);
    expect(back.to, message.to);
    expect(back.cc, message.cc);
    expect(back.bcc, message.bcc);
    expect(back.replyTo, message.replyTo);
    expect(back.subject, message.subject);
    expect(back.text, message.text);
    expect(back.html, message.html);
    expect(back.headers, message.headers);
    expect(back.tags, message.tags);
    expect(back.metadata, message.metadata);
    expect(back.attachments, hasLength(2));
    for (int i = 0; i < 2; i++) {
      Attachment a = back.attachments[i];
      Attachment b = message.attachments[i];
      expect(a.bytes, b.bytes);
      expect(a.filename, b.filename);
      expect(a.contentType, b.contentType);
      expect(a.cid, b.cid);
    }
  });

  test('Mail.queue sends nothing now, the worker sends it', () async {
    String id = await Mail.queue(_full());
    expect(id, 'job-1');
    expect(main.sent, isEmpty);
    expect(queue.pushed.single.mailer, 'main');
    expect(queue.pushed.single.delay, isNull);
    await queue.work();
    Message sent = main.messages.single;
    expect(sent.subject, 'Your invoice');
    expect(sent.bcc, <Address>[const Address('eve@example.com')]);
    expect(sent.attachments.first.bytes, <int>[0, 1, 2, 255, 128]);
  });

  test('the default from is filled in when the mail is queued', () async {
    await Mail.queue(
      Message(
        to: <Address>[const Address('ann@example.com')],
        subject: 'Hi',
        text: 'Hello',
      ),
    );
    expect(queue.pushed.single.json, contains('app@example.com'));
  });

  test('Mail.later keeps the delay, the queue name and encrypt', () async {
    await Mail.later(
      const Duration(minutes: 5),
      _full(),
      queue: 'emails',
      encrypt: true,
    );
    _Push push = queue.pushed.single;
    expect(push.delay, const Duration(minutes: 5));
    expect(push.queue, 'emails');
    expect(push.encrypt, isTrue);
  });

  test('a named mailer is kept, so the worker uses its transport', () async {
    await Mail.mailer('other').queue(_full());
    await Mail.mailer('other').later(const Duration(seconds: 1), _full());
    expect(queue.pushed.map((_Push p) => p.mailer), <String>['other', 'other']);
    await queue.work();
    expect(other.sent, hasLength(2));
    expect(main.sent, isEmpty);
  });

  test('a bad message fails when it is queued, not in the worker', () async {
    await expectLater(
      Mail.queue(Message(subject: 'x', text: 'x')),
      throwsA(isA<MailException>()),
    );
    expect(queue.pushed, isEmpty);
  });

  test('hand-built JSON with a CRLF header is refused by the worker', () async {
    Map<String, Object?> json = _full().toJson();
    json['headers'] = <String, Object?>{'X-Bad': 'a\r\nBcc: evil@example.com'};
    queue.pushed.add(_Push('main', jsonEncode(json), null, null, false));
    await expectLater(queue.work(), throwsA(isA<MailException>()));
    expect(main.sent, isEmpty);
  });

  test('with no queue, Mail.queue is a StateError', () async {
    Mail.useQueue(null);
    await expectLater(Mail.queue(_full()), throwsStateError);
  });

  group('Mail.fake', () {
    test('keeps queued mail and pushes no job', () async {
      ArrayTransport fake = Mail.fake();
      String id = await Mail.queue(_full(), queue: 'emails', encrypt: true);
      await Mail.mailer('other').later(const Duration(minutes: 5), _full());
      expect(id, 'array-job-1');
      expect(queue.pushed, isEmpty);
      expect(fake.sent, isEmpty);
      QueuedMessage first = fake.queued.first;
      expect(first.mailer, 'main');
      expect(first.queue, 'emails');
      expect(first.encrypt, isTrue);
      expect(first.delay, isNull);
      expect(first.message.subject, 'Your invoice');
      QueuedMessage second = fake.queued.last;
      expect(second.mailer, 'other');
      expect(second.delay, const Duration(minutes: 5));
    });

    test('works with no job queue', () async {
      Mail.useQueue(null);
      ArrayTransport fake = Mail.fake();
      await Mail.queue(_full());
      await Mail.later(const Duration(seconds: 1), _full());
      expect(fake.queued, hasLength(2));
    });

    test('still checks the message', () async {
      ArrayTransport fake = Mail.fake();
      await expectLater(
        Mail.queue(Message(subject: 'x', text: 'x')),
        throwsA(isA<MailException>()),
      );
      expect(fake.queued, isEmpty);
    });

    test('restore uses the real queue again', () async {
      Mail.fake();
      Mail.restore();
      await Mail.queue(_full());
      expect(queue.pushed, hasLength(1));
    });
  });
}
