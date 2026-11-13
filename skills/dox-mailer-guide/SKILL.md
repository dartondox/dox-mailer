---
name: dox-mailer-guide
description: Use when you send email in a Dox (Dart) app with dox_mailer. Covers mail config, the MailProvider, Mail.send, mailables, Markdown mail, notifications, queued mail, transports (SMTP, SES, Resend, Mailgun, Postmark, Azure, sendmail) and testing with Mail.fake.
---

# dox_mailer guide

`dox_mailer` sends email from a Dox app. You build a `Message` (or a `Mailable` class) and call `Mail.send()`. A transport sends it. You pick the transport in a config file, so you can change provider with no code change.

For routes, controllers and app layout, see the `dox-core-guide` skill.

## Install and register

1. Add the package:

```bash
dart pub add dox_mailer
```

2. Create the config in `lib/config/mail.dart`. A mailer is a name plus a transport. `defaultMailer` is the one `Mail.send()` uses.

```dart
import 'package:dox_core/dox_core.dart';
import 'package:dox_mailer/dox_mailer.dart';

MailConfig mailConfig = MailConfig(
  defaultMailer: Env.get('MAIL_MAILER', 'log'),
  from: Address(Env.get('MAIL_FROM', 'hello@example.com'), 'My app'),
  mailers: <String, Transport>{
    'smtp': SmtpTransport(
      host: Env.get('MAIL_HOST', 'localhost'),
      port: Env.get<int>('MAIL_PORT', 587),
      username: Env.get<String?>('MAIL_USERNAME'),
      password: Env.get<String?>('MAIL_PASSWORD'),
    ),
    'log': LogTransport(), // prints emails, sends nothing
  },
);
```

3. Create the provider in `lib/providers/mail_provider.dart`. Dox finds every `DoxProvider` class in `lib/` through `lib/generated/container.g.dart`, so run the Dox code generator after you add it.

```dart
import 'package:dox_mailer/dox_mailer.dart';

import '../config/mail.dart';

class AppMailProvider extends MailProvider {
  AppMailProvider() : super(mailConfig);
}
```

The provider calls `Mail.configure()` in every isolate and closes SMTP and HTTP clients when the server stops.

4. Add keys to `.env`:

```bash
MAIL_MAILER=smtp
MAIL_FROM=hello@example.com
MAIL_HOST=smtp.example.com
MAIL_PORT=587
MAIL_USERNAME=me
MAIL_PASSWORD=secret
```

`MailConfig` defaults: `defaultMailer` is `log`, `mailers` is one `log` mailer, `from` and `replyTo` are empty.

## Recipes

### 1. Send a message

```dart
import 'package:dox_mailer/dox_mailer.dart';

SentMessage sent = await Mail.send(
  Message(
    to: <Address>[Address('ann@example.com', 'Ann Lee')],
    subject: 'Welcome',
    text: 'Hello Ann, welcome!',
    html: '<p>Hello Ann, <b>welcome</b>!</p>',
  ),
);
print(sent.messageId);

await Mail.mailer('ses').send(message); // another mailer
```

A message needs a from address (or `MailConfig.from`), at least one recipient, and a text or HTML body. A line break in the subject, a header or an address is an error.

Fields of `Message`: `from`, `to`, `cc`, `bcc`, `replyTo` (lists of `Address`), `subject`, `text`, `html`, `attachments`, `headers`, `tags`, `metadata`. `Address.parse('Ann <ann@example.com>')` reads one from text.

### 2. Short forms

```dart
await Mail.raw('Your code is 1234', to: 'ann@example.com', subject: 'Your code');

await Mail.to('ann@example.com')
    .cc('Bob Lee <bob@example.com>')
    .bcc(<String>['audit@example.com'])
    .send(WelcomeMail(user));
```

`to`, `cc` and `bcc` take an `Address`, an email text, or a list of these. One text is one address. For many, pass a list.

### 3. Attachments and inline images

```dart
Message(
  to: <Address>[Address('ann@example.com')],
  subject: 'Your invoice',
  html: '<img src="cid:logo.png"> Invoice attached.',
  attachments: <Attachment>[
    Attachment(pdfBytes, 'invoice.pdf'),
    Attachment.fromFile('storage/terms.pdf'),
    Attachment.fromFile('assets/logo.png', cid: 'logo.png'),
  ],
);
```

The content type comes from the file extension. Pass `contentType` to set it. For Mailgun, use a cid with the file extension (`logo.png`).

### 4. A mailable class

One class per kind of email. Override the getters you need.

```dart
class WelcomeMail extends Mailable {
  WelcomeMail(this.user);

  final User user;

  @override
  List<Address> get to => <Address>[Address(user.email, user.name)];

  @override
  String get subject => 'Welcome';

  @override
  String? get view => 'emails/welcome'; // a dox_view template

  @override
  Map<String, Object?> get data => <String, Object?>{'name': user.name};
}

await WelcomeMail(user).send();
await WelcomeMail(user).queue();
await WelcomeMail(user).later(Duration(minutes: 10));
```

Getters: `to`, `cc`, `bcc`, `replyTo`, `from`, `subject` (required), `html`, `text`, `view`, `textView`, `markdown`, `data`, `attachments`, `mailer` (null means the default). To set headers or tags, override `toMessage()` and use `super.toMessage().copyWith(tags: <String>['welcome'])`.

### 5. Markdown mail and MailMessage

Return a template name from `markdown`. You get an HTML email with a layout and a plain text part.

```dart
@override
String? get markdown => 'emails/welcome';
```

Template `resources/views/emails/welcome.dox.html`:

```markdown
# Hi {{ name }}

[Open your profile]({{ profileUrl }})

<a href="https://example.com/dashboard" class="button">Open the app</a>
```

For a simple email with no template, use `MailMessage`:

```dart
await (MailMessage(subject: 'Invoice paid', to: <Address>[Address('ann@example.com')])
      ..line('We got your payment.')
      ..action('View invoice', 'https://example.com/invoices/1')
      ..line('Thank you!'))
    .send();
```

To use your own look, override `String layout(String body)` in a base class and return the full HTML. Wrap `body` in `SafeString` (from `dox_view`) when you render it in a template.

### 6. Notifications

`via()` picks channels. `toMail()` returns any mailable. Add the `Notifiable` mixin to the user model.

```dart
class InvoicePaid extends Notification {
  InvoicePaid(this.invoiceId);

  final int invoiceId;

  @override
  List<NotificationChannel> via(Object notifiable) {
    return <NotificationChannel>[const MailChannel()];
  }

  @override
  Mailable toMail(Object notifiable) {
    return MailMessage(subject: 'Invoice paid')
      ..line('We got your payment.')
      ..action('View invoice', 'https://example.com/invoices/$invoiceId');
  }

  @override
  bool get shouldQueue => true; // optional: send through the job queue
}

class User extends Model<User> with Notifiable {
  @override
  Object? routeNotificationFor(String channel) {
    return channel == 'mail' ? Address(email!, name) : null;
  }
}

await user.notify(InvoicePaid(1));
await Notification.send(users, InvoicePaid(1));
```

When a channel fails, the others still run. `Notification.send()` then throws a `NotificationException` (its `errors` list has the details). With one notifiable and one error, the original error is thrown. For a custom channel, implement `NotificationChannel.send(notifiable, notification)`. `dox_mailer` has no database channel.

### 7. Queue an email

Uses `dox_queue` (a dependency of dox_mailer). Add the dox_queue `QueueProvider` and run a worker. The worker sends the finished email. The mail jobs are in dox_mailer. `build_runner` with `dox_builder` adds them to `lib/generated/jobs.g.dart`. The worker (`bin/queue.dart`) must still run `MailProvider`: the job sends with the mail config that `MailProvider` sets up. Without it, the job fails with "Mail is not set up".

```dart
String jobId = await Mail.queue(message);
await Mail.later(Duration(minutes: 10), message);
await Mail.mailer('ses').queue(message, queue: 'emails', encrypt: true);
```

Options: `queue` (default `default`), `encrypt` (default `false`). The whole email, with attachments in base64, is stored in Redis or the `jobs` table. Keep attachments small. Use `encrypt: true` when others can read the store. `Mail.useQueue(queue)` sets another queue (`null`: back to the dox_queue queue).

### 8. Staging safety and hooks

Do this in `setup()` of your provider, after `super.setup()`. Each isolate has its own value, so `main()` does not reach the queue worker.

```dart
class AppMailProvider extends MailProvider {
  AppMailProvider() : super(mailConfig);

  @override
  void setup() {
    super.setup();
    Mail.clearHooks();
    if (Env.get<String>('APP_ENV') == 'staging') {
      Mail.alwaysTo('qa@example.com'); // all mail goes here, cc and bcc cleared
    }
    Mail.onSending((Message message) => print('to ${message.to}'));
  }
}
```

An `onSending` hook that throws stops the send. An `onSent` hook that throws is only logged, so a queue job is not retried and the email is not sent twice.

### 9. Test

```dart
ArrayTransport mail = Mail.fake();
await signUp('ann@example.com');
expect(mail.sent.single.message.subject, 'Welcome');
expect(mail.queued, isEmpty); // Mail.queue and Mail.later go to mail.queued
Mail.restore();
```

`Mail.fake()` needs no real queue. Each `QueuedMessage` has `message`, `mailer`, `id`, `delay`, `queue` and `encrypt`. `mail.messages` lists the sent messages.

## Transports

- `SmtpTransport(host:, port:, username:, password:, encryption: SmtpEncryption.starttls, keepAlive:, ...)`. Default port is 587 for `starttls`, 465 for `tls`, 25 for `none`. `auth` can be `SmtpAuth.plain`, `login` or `xoauth2`. `allowInsecure: true` only for test servers. For Mailpit use port 1025 with `SmtpEncryption.none`.
- `SesV2Transport(key:, secret:, region:)` and `SesTransport` (API v1). Also `sessionToken`, `configurationSet`, `endpoint`.
- `AzureTransport(endpoint:, accessKey:)` or `AzureTransport.fromConnectionString(...)`.
- `ResendTransport(apiKey:)`.
- `MailgunTransport(apiKey:, domain:, region: MailgunRegion.eu)`.
- `PostmarkTransport(serverToken:, messageStream:)`.
- `SendmailTransport(path:, mode: SendmailMode.smtp)` or `SendmailMode.pipe`.
- `LogTransport(bothBodies:, output:)` and `ArrayTransport()`.
- `FailoverTransport(<Transport>[ses, smtp], onError: ...)` tries each in order and throws the last error.

## Gotchas

- Always `await` the send. It throws a `MailException` (with `statusCode` and `body`) when the provider refuses it.
- The default mailer is `log`. If `MAIL_MAILER` is not set, nothing is really sent.
- `Mail.send` before `Mail.configure` throws a `StateError`. Add the provider.
- `Queue.fake()` catches `Mail.queue()` on the default queue, not a custom queue from `Mail.useQueue()`.
- `Mail.mailer('x')` with an unknown name throws an `ArgumentError`.
- `queue()` and `later()` render templates at once. The worker needs no templates.
- `{{ }}` in Markdown mail escapes user text. Raw HTML like `<a href="{{ url }}">` is not checked. Use only URLs your app builds. `MailMessage.action()` throws an `ArgumentError` for an unsafe URL.
- Do not indent Markdown inside `@if` or `@each`. Four spaces make a code block.
- With `starttls`, the send fails if the server has no STARTTLS. Your password is never sent in plain text.
