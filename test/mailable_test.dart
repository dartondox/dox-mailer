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
  _InvoicePaid({this.queued = false});

  final bool queued;

  @override
  bool get shouldQueue => queued;

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

  @override
  Future<String> push(
    String mailer,
    Message message, {
    Duration? delay,
    String? queue,
    bool encrypt = false,
  }) async {
    pushed.add(message);
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

  group('MailMessage', () {
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
      expect(queue.pushed.single.to.single.email, 'ann@example.com');
      expect(mail.messages, isEmpty);
    });

    test('no mail address throws', () async {
      await expectLater(
        _User(null).notify(_InvoicePaid()),
        throwsA(isA<MailException>()),
      );
    });
  });
}
