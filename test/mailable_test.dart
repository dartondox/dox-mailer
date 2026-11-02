import 'dart:io';

import 'package:dox_mailer/dox_mailer.dart';
import 'package:dox_view/dox_view.dart';
import 'package:test/test.dart';

class _WelcomeMail extends Mailable {
  _WelcomeMail(this.name, {this.template});

  final String name;
  final String? template;

  @override
  List<Address> get to => <Address>[const Address('ann@example.com')];

  @override
  String get subject => 'Welcome';

  @override
  String? get markdown => template == 'markdown' ? 'welcome' : null;

  @override
  String? get view => template == 'view' ? 'welcome_html' : null;

  @override
  String? get textView => template == 'view' ? 'welcome_text' : null;

  @override
  String? get text => template == null ? 'Hi $name' : null;

  @override
  Map<String, Object?> get data => <String, Object?>{'name': name};
}

class _TemplateMail extends Mailable {
  _TemplateMail(this.markdown, this.data);

  @override
  final String markdown;

  @override
  final Map<String, Object?> data;

  @override
  List<Address> get to => <Address>[const Address('ann@example.com')];

  @override
  String get subject => 'Hi';
}

class _ListUser with Notifiable {
  @override
  Object? routeNotificationFor(String channel) {
    return <Object>[const Address('a@example.com'), 'B <b@example.com>'];
  }
}

/// [via] throws for a notifiable that is not an [Address]
class _PickyNotification extends Notification {
  @override
  List<NotificationChannel> via(Object notifiable) {
    if (notifiable is! Address) throw StateError('no channel');
    return <NotificationChannel>[const MailChannel()];
  }

  @override
  Mailable toMail(Object notifiable) => MailMessage()..line('Hi');
}

class _User with Notifiable {
  _User(this.email);

  final String? email;
  final List<String> saved = <String>[];

  @override
  Object? routeNotificationFor(String channel) {
    return channel == 'mail' ? email : null;
  }
}

/// a channel of the app, like a database channel
class _SaveChannel implements NotificationChannel {
  @override
  Future<void> send(Object notifiable, Notification notification) async {
    (notifiable as _User).saved.add('${notification.toArray(notifiable)}');
  }
}

class _InvoicePaid extends Notification {
  _InvoicePaid({this.queued = false, this.wait});

  final bool queued;
  final Duration? wait;

  @override
  bool get shouldQueue => queued;

  @override
  Duration? get delay => wait;

  @override
  String? get queue => queued ? 'mail' : null;

  @override
  List<NotificationChannel> via(Object notifiable) {
    return <NotificationChannel>[
      const MailChannel(),
      if (notifiable is _User) _SaveChannel(),
    ];
  }

  @override
  Mailable toMail(Object notifiable) {
    return MailMessage(subject: 'Invoice paid', salutation: 'Regards, Acme')
      ..line('We got your payment <3')
      ..action('View invoice', 'https://example.com/i?a=1&b=2');
  }

  @override
  Map<String, Object?> toArray(Object notifiable) {
    return <String, Object?>{'invoice': 1};
  }
}

class _FakeQueue implements MailQueue {
  final List<Message> pushed = <Message>[];
  final List<String> options = <String>[];

  @override
  Future<String> push(
    String mailer,
    Message message, {
    Duration? delay,
    String? queue,
    bool encrypt = false,
  }) async {
    pushed.add(message);
    options.add('$delay $queue $encrypt');
    return 'job-${pushed.length}';
  }
}

void main() {
  late ArrayTransport mail;
  late Directory views;

  setUpAll(() {
    views = Directory.systemTemp.createTempSync('dox_mailer_views');
    File('${views.path}/welcome.dox.html')
        .writeAsStringSync('# Hi {{ name }}\n\nThanks for joining.\n');
    File('${views.path}/welcome_html.dox.html')
        .writeAsStringSync('<p>Hi {{ name }}</p>');
    File('${views.path}/welcome_text.dox.html')
        .writeAsStringSync('Hi {{ name }}');
    File('${views.path}/links.dox.html').writeAsStringSync(
      'Hi {{ name }}\n\n[site](https://example.com/a:b) [me](mailto:a@b.c) '
      '[rel](/x?y=a:b) ![logo](cid:logo)\n',
    );
    File('${views.path}/raw.dox.html').writeAsStringSync(
      'https://example.com/?a=1&b=2\n\n'
      '[x](https://example.com/?c=3&d=4)\n\n'
      '[a](javascript&amp;#58;alert(1)) [b](javascript&#x3A;x) '
      '[c](javascript&colon;x) [d](&#106;avascript:x) '
      '![e](data&#58;image/png;base64,xx) <javascript&#58;y>\n',
    );
    View.configure(ViewConfig(path: views.path, cache: false));
  });

  tearDownAll(() {
    views.deleteSync(recursive: true);
  });

  setUp(() {
    Mail.configure(MailConfig(from: const Address('app@example.com')));
    mail = Mail.fake();
  });

  tearDown(() {
    Mail.restore();
    Mail.useQueue(null);
  });

  group('Mailable', () {
    test('send() uses the getters and the default from', () async {
      await _WelcomeMail('Ann').send();
      Message sent = mail.messages.single;
      expect(sent.from!.email, 'app@example.com');
      expect(sent.to.single.email, 'ann@example.com');
      expect(sent.subject, 'Welcome');
      expect(sent.text, 'Hi Ann');
      expect(sent.html, isNull);
    });

    test('view and textView render dox_view templates', () {
      Message message = _WelcomeMail(
        'Tom & Jerry',
        template: 'view',
      ).toMessage();
      expect(message.html, '<p>Hi Tom &amp; Jerry</p>');
      expect(message.text, 'Hi Tom & Jerry');
    });

    test('markdown is HTML in the layout, and the text is the Markdown', () {
      Message message = _WelcomeMail(
        '<b>Ann</b>',
        template: 'markdown',
      ).toMessage();
      expect(message.html, contains('<h1>Hi &lt;b&gt;Ann&lt;/b&gt;</h1>'));
      expect(message.html, contains('<p>Thanks for joining.</p>'));
      expect(message.html, startsWith('<!DOCTYPE html>'));
      expect(message.text, '# Hi <b>Ann</b>\n\nThanks for joining.\n');
    });

    test('queue() puts the rendered email on the queue', () async {
      _FakeQueue queue = _FakeQueue();
      Mail.useQueue(queue);
      String id = await _WelcomeMail('Ann', template: 'markdown').queue();
      expect(id, 'job-1');
      expect(queue.pushed.single.html, contains('<h1>Hi Ann</h1>'));
      expect(queue.pushed.single.from!.email, 'app@example.com');
      expect(mail.messages, isEmpty);
    });
  });

  group('unsafe links', () {
    const String bad =
        '[a](javascript:alert(1)) [b](JaVa&#115;cript&#58;x) '
        '[c]( vbscript:x ) ![d](data:image/png;base64,xx) <javascript:y>';

    void expectNoUnsafeUrl(String html) {
      // no href or src with a `javascript:`, `vbscript:` or `data:` URL
      expect(html, isNot(contains(RegExp('(href|src)="[^"]*(script|data):'))));
    }

    test('a MailMessage line loses unsafe links', () {
      String html = (MailMessage()..line(bad)).toMessage().html!;
      expectNoUnsafeUrl(html);
      expect(html, contains('<a>a</a>'));
      expect(html, contains('<a>b</a>'));
      expect(html, contains('<img alt="d" />'));
    });

    test('{{ }} in a markdown template loses unsafe links', () {
      String html = _TemplateMail('links', <String, Object?>{
        'name': bad,
      }).toMessage().html!;
      expectNoUnsafeUrl(html);
      expect(html, contains('<a href="https://example.com/a:b">site</a>'));
      expect(html, contains('<a href="mailto:a@b.c">me</a>'));
      expect(html, contains('<a href="/x?y=a:b">rel</a>'));
      expect(html, contains('src="cid:logo"'));
    });
  });

  group('links with &', () {
    test('a bare URL and a [x](url) link escape & once', () {
      String html =
          (MailMessage()
                ..line('https://example.com/?a=1&b=2')
                ..line('[x](https://example.com/?c=3&d=4)'))
              .toMessage()
              .html!;
      expect(html, contains('href="https://example.com/?a=1&amp;b=2"'));
      expect(html, contains('href="https://example.com/?c=3&amp;d=4"'));
      expect(html, isNot(contains('&amp;amp;')));
    });

    test('raw Markdown: & once, and encoded javascript: stays blocked', () {
      String html = _TemplateMail(
        'raw',
        const <String, Object?>{},
      ).toMessage().html!;
      expect(html, contains('href="https://example.com/?a=1&amp;b=2"'));
      expect(html, contains('href="https://example.com/?c=3&amp;d=4"'));
      expect(html, isNot(contains('&amp;amp;')));
      expect(html, contains('<a>a</a>'));
      expect(html, contains('<a>b</a>'));
      expect(html, contains('<a>d</a>'));
      expect(html, contains('<img alt="e" />'));
      expect(html, contains('<a>c</a>'));
      expect(html, isNot(contains(RegExp('(href|src)="[^"]*(script|data):'))));
    });
  });

  group('MailMessage', () {
    test('cc, attach() and error()', () {
      Message message =
          (MailMessage(cc: <Address>[const Address('c@x.io')])
                ..attach(Attachment(<int>[1, 2], 'a.pdf'))
                ..error()
                ..action('Retry', 'https://example.com/retry'))
              .toMessage();
      expect(message.cc.single.email, 'c@x.io');
      expect(message.attachments.single.filename, 'a.pdf');
      expect(message.html, contains('class="button button-error">Retry</a>'));
    });

    test('action() throws for an unsafe URL', () {
      for (String url in <String>[
        'javascript:alert(1)',
        ' JavaScript:alert(1)',
        'java\tscript:x',
        'data:text/html,x',
        'vbscript:x',
      ]) {
        expect(
          () => MailMessage().action('Go', url),
          throwsArgumentError,
          reason: url,
        );
      }
      for (String url in <String>[
        'https://example.com/a:b',
        'mailto:a@b.c',
        '/reset?token=a:b',
      ]) {
        MailMessage().action('Go', url);
      }
    });

    test('escapes lines and makes a button', () {
      Message message =
          (MailMessage(subject: 'Hi')
                ..line('a <b> line')
                ..action('Open', 'https://example.com/?a=1&b=2'))
              .toMessage();
      expect(message.html, contains('<strong>Hello!</strong>'));
      expect(message.html, contains('a &lt;b&gt; line'));
      expect(
        message.html,
        contains(
          '<a href="https://example.com/?a=1&amp;b=2" class="button">Open</a>',
        ),
      );
      expect(
        message.text,
        'Hello!\n\na <b> line\n\nOpen: https://example.com/?a=1&b=2',
      );
    });
  });

  group('Notification', () {
    test('notify() sends on every channel', () async {
      _User user = _User('Ann <ann@example.com>');
      await user.notify(_InvoicePaid());
      Message sent = mail.messages.single;
      expect(sent.to.single.email, 'ann@example.com');
      expect(sent.to.single.name, 'Ann');
      expect(sent.subject, 'Invoice paid');
      expect(sent.text, contains('Regards, Acme'));
      expect(user.saved, <String>['{invoice: 1}']);
    });

    test('Notification.send() takes an Address with no user', () async {
      await Notification.send(<Object>[
        const Address('a@example.com'),
        const Address('b@example.com'),
      ], _InvoicePaid());
      expect(mail.messages.map((Message m) => m.to.single.email), <String>[
        'a@example.com',
        'b@example.com',
      ]);
    });

    test('shouldQueue puts the email on the queue', () async {
      _FakeQueue queue = _FakeQueue();
      Mail.useQueue(queue);
      await _User('ann@example.com').notify(_InvoicePaid(queued: true));
      await _User('bob@example.com')
          .notify(_InvoicePaid(queued: true, wait: const Duration(minutes: 5)));
      expect(queue.pushed.first.to.single.email, 'ann@example.com');
      expect(queue.options, <String>[
        'null mail false',
        '0:05:00.000000 mail false',
      ]);
      expect(mail.messages, isEmpty);
    });

    test('a failed send does not stop the others', () async {
      _User noAddress = _User(null);
      _User bob = _User('bob@example.com');
      Object? thrown;
      try {
        await Notification.send(<Object>[noAddress, bob], _InvoicePaid());
      } catch (error) {
        thrown = error;
      }
      NotificationException e = thrown! as NotificationException;
      expect(e.errors.single.notifiable, noAddress);
      expect(e.errors.single.error, isA<MailException>());
      // the other channel of the same user, and the next user, still ran
      expect(noAddress.saved, hasLength(1));
      expect(mail.messages.single.to.single.email, 'bob@example.com');
      expect(bob.saved, hasLength(1));
      expect(
        '$e',
        allOf(contains('1 failed'), contains('on MailChannel: MailException')),
      );
    });

    test('one notifiable and one error: the error as it is', () async {
      _User user = _User(null);
      await expectLater(
        user.notify(_InvoicePaid()),
        throwsA(isA<MailException>()),
      );
      expect(user.saved, hasLength(1));
    });

    test('a failed via() does not stop the others', () async {
      Object? thrown;
      try {
        await Notification.send(<Object>[
          'not a user',
          _User('Ann <ann@example.com>'),
          const Address('b@example.com'),
        ], _PickyNotification());
      } catch (error) {
        thrown = error;
      }
      NotificationException e = thrown! as NotificationException;
      expect(e.errors.first.channel, isNull);
      expect('$e', contains('- not a user on via(): Bad state: no channel'));
      expect('$e', contains('- _User (Ann <ann@example.com>) on via()'));
      expect(mail.messages.single.to.single.email, 'b@example.com');
    });

    test('the mail route can be a list of addresses and email texts', () async {
      await _ListUser().notify(_InvoicePaid());
      expect(mail.messages.single.to.map((Address a) => a.email), <String>[
        'a@example.com',
        'b@example.com',
      ]);
    });
  });
}
