import 'dart:async';

import 'package:dox_core/dox_core.dart' show AppConfig, Dox, LoggerConfig;
import 'package:dox_mailer/dox_mailer.dart';
import 'package:dox_queue/dox_queue.dart';
import 'package:test/test.dart';

import 'memory_queue.dart';

late ArrayTransport mainMailer;
late ArrayTransport otherMailer;

/// a mail server that is down
class BrokenTransport extends Transport {
  int calls = 0;

  @override
  Future<SentMessage> send(Message message) async {
    calls++;
    throw MailException('server is down');
  }
}

late BrokenTransport brokenMailer;

class _CustomQueue implements MailQueue {
  @override
  Future<String> push(
    String mailer,
    Message message, {
    Duration? delay,
    String? queue,
    bool encrypt = false,
  }) async => 'id';
}

/// a mail server that says no, and names the recipient and the subject,
/// like many SMTP servers do
class RejectTransport extends Transport {
  @override
  Future<SentMessage> send(Message message) async {
    throw MailException(
      '550 5.1.1 <ANN@example.com>: mailbox unavailable '
      '(subject "Your invoice", for Ann, forwarded to ann.lee@other.org)',
      statusCode: 550,
    );
  }
}

/// a mail server that quotes the whole body in its answer
class QuoteTransport extends Transport {
  @override
  Future<SentMessage> send(Message message) async {
    throw MailException(
      '552 message refused: ${message.html}',
      statusCode: 552,
    );
  }
}

/// the parts of the test mail that must not be in a log
const List<String> _secrets = <String>[
  'ann@example.com',
  'ann.lee@other.org',
  'Your invoice',
  'Ann',
];

Message _message() => Message(
  to: <Address>[const Address('ann@example.com', 'Ann')],
  bcc: <Address>[const Address('boss@example.com')],
  subject: 'Your invoice',
  text: 'Hi Ann',
  html: '<p>Hi Ann</p>',
  attachments: <Attachment>[
    Attachment(<int>[0, 1, 2, 255], 'invoice.pdf'),
  ],
);

/// take one job of [queue] and run it with an app registry that has no
/// mail job, like a real app
Future<JobPayload> _work([String queue = 'default', int tries = 1]) async {
  ReservedJob? job = await Queue.driver.pop(queue);
  expect(job, isNotNull, reason: 'no job on $queue');
  await Worker(
    driver: Queue.driver,
    jobs: const JobRegistry(<JobCodec>[]),
    options: WorkerOptions(tries: tries),
  ).process(job!);
  return job.payload;
}

void main() {
  setUpAll(() {
    Queue.extend('memory', MemoryQueueFactory());
    // log on, so the tests can read what the worker logs
    Dox().initialize(
      AppConfig(
        appKey: 'k' * 32,
        totalIsolate: 1,
        logger: LoggerConfig(enabled: true),
      ),
    );
  });

  setUp(() {
    Mail.restore();
    mainMailer = ArrayTransport();
    otherMailer = ArrayTransport();
    brokenMailer = BrokenTransport();
    Mail.configure(
      MailConfig(
        defaultMailer: 'main',
        from: const Address('app@example.com', 'App'),
        mailers: <String, Transport>{
          'main': mainMailer,
          'other': otherMailer,
          'broken': brokenMailer,
          'reject': RejectTransport(),
          'quote': QuoteTransport(),
        },
      ),
    );
  });

  tearDown(Queue.close);

  test('Queue.fake() catches Mail.queue() and Mail.later()', () async {
    QueueFake queue = Queue.fake();
    addTearDown(Queue.restore);
    await Mail.queue(_message());
    await Mail.later(Duration(minutes: 1), _message(), queue: 'mail');
    expect(mainMailer.sent, isEmpty);
    expect(queue.pushed, hasLength(2));
    expect(queue.pushed.last.queue, 'mail');
    expect(queue.pushed.last.delay, Duration(minutes: 1));
    queue.assertPushedTimes<SendQueuedMail>(2);
    queue.assertNotPushed<SendEncryptedQueuedMail>();
  });

  test('Mail.useQueue() wins over the dox_queue queue', () {
    expect(Mail.mailQueue, isA<QueueMailQueue>());
    _CustomQueue custom = _CustomQueue();
    Mail.useQueue(custom);
    addTearDown(() => Mail.useQueue(null));
    expect(Mail.mailQueue, same(custom));
  });

  test(
    'Mail.fake() wins over Queue.fake(), restore gives the queue back',
    () async {
      _CustomQueue custom = _CustomQueue();
      Mail.useQueue(custom);
      addTearDown(() => Mail.useQueue(null));
      QueueFake queue = Queue.fake();
      addTearDown(Queue.restore);
      ArrayTransport mail = Mail.fake();
      await Mail.queue(_message());
      expect(mail.queued, hasLength(1));
      queue.assertNothingPushed();
      Mail.restore();
      expect(Mail.mailQueue, same(custom));
      Mail.useQueue(null);
      await Mail.queue(_message());
      queue.assertPushedTimes<SendQueuedMail>(1);
    },
  );

  test('with the sync driver, Mail.queue sends at once', () async {
    Queue.configure(QueueConfig());
    await Mail.mailer('other').queue(_message());
    expect(otherMailer.messages.single.subject, 'Your invoice');
    expect(mainMailer.sent, isEmpty);
  });

  group('a queue with a worker', () {
    setUp(() {
      Queue.configure(QueueConfig(driver: 'memory'));
    });

    test('a plain mail job saved by 3.1 still sends', () async {
      await Queue.driver.push(JobPayload.decode(_saved31Plain));
      JobPayload payload = await _work();
      expect(payload.job, 'dox_queue:SendQueuedMail');
      Message sent = mainMailer.messages.single;
      expect(sent.subject, 'Old job');
      expect(sent.text, 'Saved by 3.1');
      expect(await Queue.driver.failed(), isEmpty);
    });

    test('an encrypted mail job saved by 3.1 still sends', () async {
      await Queue.driver.push(JobPayload.decode(_saved31Encrypted));
      JobPayload payload = await _work();
      expect(payload.job, 'dox_queue:SendEncryptedQueuedMail');
      expect(mainMailer.messages.single.subject, 'Old job');
      expect(await Queue.driver.failed(), isEmpty);
    });

    test('Mail.queue saves the mail, the worker sends it', () async {
      String id = await Mail.queue(_message());
      expect(mainMailer.sent, isEmpty);
      JobPayload payload = await _work();
      expect(payload.id, id);
      expect(payload.job, 'dox_queue:SendQueuedMail');
      Message sent = mainMailer.messages.single;
      expect(sent.from, const Address('app@example.com', 'App'));
      expect(sent.to, <Address>[const Address('ann@example.com', 'Ann')]);
      expect(sent.bcc, <Address>[const Address('boss@example.com')]);
      expect(sent.html, '<p>Hi Ann</p>');
      expect(sent.attachments.single.bytes, <int>[0, 1, 2, 255]);
      expect(sent.attachments.single.contentType, 'application/pdf');
      expect(await Queue.driver.failed(), isEmpty);
    });

    test('the worker sends with the same mailer', () async {
      await Mail.mailer('other').queue(_message(), queue: 'emails');
      await _work('emails');
      expect(otherMailer.sent, hasLength(1));
      expect(mainMailer.sent, isEmpty);
    });

    test('Mail.later waits for the delay', () async {
      await Mail.later(const Duration(minutes: 5), _message());
      expect(await Queue.driver.pop('default'), isNull);
      expect(mainMailer.sent, isEmpty);
    });

    test('a failing transport is retried, then the job fails', () async {
      await Mail.mailer('broken').queue(_message());
      await _work('default', 2);
      expect(brokenMailer.calls, 1);
      expect(await Queue.driver.failed(), isEmpty);
      await _work('default', 2);
      expect(brokenMailer.calls, 2);
      List<FailedJob> failed = await Queue.driver.failed();
      expect(failed.single.job, 'dox_queue:SendQueuedMail');
      expect(failed.single.error, contains('server is down'));
      expect(await Queue.driver.pop('default'), isNull);
    });

    test('encrypt: true: a send error shows no mail data', () async {
      await Mail.mailer('reject').queue(_message(), encrypt: true);
      String log = await logOf(_retryThenFail);
      List<FailedJob> failed = await Queue.driver.failed();
      String error = failed.single.error;
      // the encrypted details are random base64 text, and a short
      // secret like "Ann" can be in it by chance. Check the text
      // around them only.
      String plainLog = log.replaceAll(_encrypted, '');
      String plainError = error.replaceAll(_encrypted, '');
      for (String secret in _secrets) {
        expect(plainLog, isNot(contains(secret)));
        expect(plainError, isNot(contains(secret)));
      }
      // still enough to find the problem
      printOnFailure(log);
      expect(log, contains('failed try 1 of 2'));
      expect(log, contains('RedactedMailError: MailException (code 550).'));
      expect(error, contains('RedactedMailError: MailException (code 550).'));
      // the app key gives back the full error
      expect(
        RedactedMailError.decrypt(error),
        startsWith('MailException: 550 5.1.1 <ANN@example.com>'),
      );
    });

    test('encrypt: true: a 100 KB body is not in the error', () async {
      String html = '<p>Your reset code is 918273</p>${'x' * 100 * 1024}';
      Message message = _message().copyWith(html: html);
      await Mail.mailer('quote').queue(message, encrypt: true);
      String log = await logOf(_retryThenFail);
      String error = (await Queue.driver.failed()).single.error;
      for (String text in <String>[log, error]) {
        // the encrypted details are random base64 text. About 1 in 300
        // has "xxxx" in it by chance, and each run makes several. Check
        // the text around them only.
        text = text.replaceAll(_encrypted, 'Details are encrypted: ...');
        expect(text, isNot(contains('918273')));
        expect(text, isNot(contains('xxxx')));
        expect(text, contains('MailException (code 552). Details are'));
      }
    });

    test('a plain mail job keeps the full error, as before', () async {
      await Mail.mailer('reject').queue(_message());
      await logOf(_retryThenFail);
      List<FailedJob> failed = await Queue.driver.failed();
      expect(failed.single.error, contains('<ANN@example.com>'));
    });

    test('encrypt: true saves the mail encrypted', () async {
      await Mail.queue(_message(), encrypt: true);
      JobPayload payload = await _work();
      expect(payload.job, 'dox_queue:SendEncryptedQueuedMail');
      expect(payload.data, isNot(contains('ann@example.com')));
      expect(payload.data, isNot(contains('Your invoice')));
      expect(payload.data, isNot(contains('Hi Ann')));
      expect(mainMailer.messages.single.subject, 'Your invoice');
    });
  });
}

/// A mail job as dox_queue 3.1 saved it (`JobPayload.encode()`), with
/// the job name and data of 3.1.
const String _saved31Plain =
    '{"id":"0123456789abcdef0123456789abcdef",'
    '"job":"dox_queue:SendQueuedMail","queue":"default",'
    '"data":"{\\"mailer\\":\\"main\\",\\"message\\":{\\"from\\":null,'
    '\\"to\\":[{\\"email\\":\\"ann@example.com\\",\\"name\\":null}],'
    '\\"cc\\":[],\\"bcc\\":[],\\"replyTo\\":[],\\"subject\\":\\"Old job\\",'
    '\\"text\\":\\"Saved by 3.1\\",\\"html\\":null,\\"attachments\\":[],'
    '\\"headers\\":{},\\"tags\\":[],\\"metadata\\":{}}}",'
    '"attempts":0}';

/// The same mail with `encrypt: true`, encrypted with the app key
/// `'k' * 32`, as dox_queue 3.1 saved it.
const String _saved31Encrypted =
    '{"id":"fedcba9876543210fedcba9876543210",'
    '"job":"dox_queue:SendEncryptedQueuedMail","queue":"default",'
    '"data":"IPB+h2NNwltf83cWykAIkmPv1aZ/JG8qF81RAGEduCnLJQGdXShrHXC9nUf/viPe'
    'qp31wkgrgcQBV0UdaVSdfeSKBJCn2wd7XweJ47GMlH+pQLU4cGJS2qQDjJ9lh8Xj68XseLGY'
    'D1WDbBIhnRo1ib7vl+yoCsVE9OqzHpv1oMD9NcXH5e5HSYB0dzxHez1NOVak5KaTHmqqoqLP'
    'Lfw2WDR6CVz3WiTiXzlzlCx+yc+9O1uUfZytFQzV/FrIxbV4khHz0I+NsTUTvMTLIhrdm68n'
    '4Npf4JKskax/hh8wzUdSeyrazucdZbtm8/ZWmiY/HoeRsVuq5CHbSBNYTm4=",'
    '"attempts":0}';

/// the encrypted details of a [RedactedMailError] text
final RegExp _encrypted = RegExp(r'Details are encrypted: [^\s"]+');

/// two tries: the first is released, the second fails
Future<void> _retryThenFail() async {
  await _work('default', 2);
  await _work('default', 2);
}
