# dox_mailer

Send email from the [Dox](https://dartondox.dev) framework: SMTP, Amazon SES, Azure, Resend, Mailgun, Postmark and sendmail.

You write a `Message` and call `Mail.send()`. A transport sends it. You pick the transport in a config file, so you can change providers with no code change.

It also has mailables (one class per email, with dox_view or Markdown templates) and notifications (one message, sent on mail or your own channels).

The package has its own SMTP client, AWS signer and MIME builder. It does not import `dox_core` itself, but `dox_view` still uses it. It needs `dox_view`, `markdown`, `http` and `crypto`.

## Install

```bash
dart pub add dox_mailer
```

## Set up

### 1. Config

A mailer is a name and a transport. `defaultMailer` is the one that `Mail.send()` uses.

`lib/config/mail.dart`:

```dart
import 'package:dox_core/dox_core.dart';
import 'package:dox_mailer/dox_mailer.dart';

MailConfig mailConfig = MailConfig(
  /// the mailer of Mail.send()
  defaultMailer: Env.get('MAIL_MAILER', 'log'),

  /// for messages with no from address
  from: Address(Env.get('MAIL_FROM', 'hello@example.com'), 'My app'),

  mailers: <String, Transport>{
    'smtp': SmtpTransport(
      host: Env.get('MAIL_HOST', 'localhost'),
      port: Env.get<int>('MAIL_PORT', 587),
      username: Env.get<String?>('MAIL_USERNAME'),
      password: Env.get<String?>('MAIL_PASSWORD'),
    ),

    /// prints emails, sends nothing
    'log': LogTransport(),
  },
);
```

`Env.get()` reads the `.env` file and the real environment. You can also add the keys to the `AppEnv` class of your app and use `env.mailHost`.

`.env`:

```
MAIL_MAILER=smtp
MAIL_FROM=hello@example.com
MAIL_HOST=smtp.example.com
MAIL_PORT=587
MAIL_USERNAME=me
MAIL_PASSWORD=secret
```

| Option | Default | What it does |
| --- | --- | --- |
| `defaultMailer` | `log` | the mailer of `Mail.send()` |
| `mailers` | a `log` mailer | each mailer name and its transport |
| `from` | none | the from address of a message that has none |
| `replyTo` | none | the reply-to addresses of a message that has none |

### 2. Provider

The provider sets up the mailers in every isolate. Put it in `lib/` so the generated container finds it.

`lib/providers/mail_provider.dart`:

```dart
import 'package:dox_mailer/dox_mailer.dart';

import '../config/mail.dart';

/// Sets up the mailers. Dox finds every DoxProvider class,
/// see lib/generated/container.g.dart.
class AppMailProvider extends MailProvider {
  AppMailProvider() : super(mailConfig);
}
```

When the server stops, the provider closes open SMTP connections and HTTP clients.

## Send an email

```dart
import 'package:dox_mailer/dox_mailer.dart';

await Mail.send(
  Message(
    to: <Address>[Address('ann@example.com', 'Ann Lee')],
    subject: 'Welcome',
    text: 'Hello Ann, welcome!',
    html: '<p>Hello Ann, <b>welcome</b>!</p>',
  ),
);
```

Send with another mailer:

```dart
await Mail.mailer('ses').send(message);
```

`send()` gives a `SentMessage`. Its `messageId` is the id of the provider (or the `Message-ID` header for SMTP and sendmail).

When the message can not be sent, `send()` throws a `MailException`. It has the `statusCode` and the `body` of the answer of the server.

### Short ways to send

`Mail.raw()` sends a plain text email. `Mail.to()` starts an email with chained calls. Both take plain email text:

```dart
await Mail.raw('Your code is 1234', to: 'ann@example.com', subject: 'Your code');

await Mail.to('ann@example.com')
    .cc('Bob Lee <bob@example.com>')
    .bcc(<String>['audit@example.com'])
    .send(WelcomeMail(user));
```

- `to()`, `cc()` and `bcc()` take an `Address`, an email text, or a list of these.
- `send()` takes a mailable. The recipients are added to the ones of the mailable.
- `queue()` and `later()` work too, like `Mail.to(email).queue(WelcomeMail(user))`.
- `Address.list()` reads addresses the same way: `Message(to: Address.list('ann@example.com'), ...)`.
- One text is one address. For more addresses, pass a list: `Address.list(<String>['ann@example.com', 'bob@example.com'])`.

### The message

| Field | What it is |
| --- | --- |
| `from` | an `Address`. Null: `MailConfig.from` |
| `to`, `cc`, `bcc` | lists of `Address` |
| `replyTo` | a list of `Address` |
| `subject` | text |
| `text` | the plain text body |
| `html` | the HTML body |
| `attachments` | a list of `Attachment` |
| `headers` | extra headers, like `{'X-Campaign': 'fall'}` |
| `tags` | tags for the reports of the provider |
| `metadata` | key and value data for the provider, like `{'user_id': '42'}` |

An `Address` is an email and an optional name: `Address('ann@example.com', 'Ann')`. `Address.parse('Ann <ann@example.com>')` reads one from text.

A message needs a from address, at least one recipient, and a text or HTML body. A subject or header with a line break is an error, so user input can not add headers.

### Attachments

```dart
Message(
  to: <Address>[Address('ann@example.com')],
  subject: 'Your invoice',
  text: 'The invoice is attached.',
  attachments: <Attachment>[
    Attachment(pdfBytes, 'invoice.pdf'),
    Attachment.fromFile('storage/terms.pdf'),
  ],
);
```

The content type comes from the file extension. Pass `contentType` to set it.

To attach a file from a storage disk, like S3, read its bytes first. This works with every disk:

```dart
Uint8List? pdf = await Storage().disk('s3').get('invoices/42.pdf');
Attachment(pdf!, 'invoice.pdf');
```

### Inline images

Give the file a `cid`. Use it in the HTML with `cid:`.

```dart
Message(
  to: <Address>[Address('ann@example.com')],
  subject: 'Hello',
  html: '<img src="cid:logo.png"> Hello!',
  attachments: <Attachment>[
    Attachment.fromFile('assets/logo.png', cid: 'logo.png'),
  ],
);
```

Mailgun uses the file name as the cid. So for Mailgun, use a cid like `logo.png`, with the file extension.

### HTML from a view

With [dox_view](https://pub.dev/packages/dox_view), render a template to HTML:

```dart
String html = View.render('emails/welcome', <String, dynamic>{'name': 'Ann'});
await Mail.send(Message(to: to, subject: 'Welcome', html: html));
```

## Queue an email

Sending an email can take a second or more. With a queue, the request does not wait. A queue worker sends the email later.

This needs [dox_queue](https://pub.dev/packages/dox_queue). Set up its config, its provider and a worker first. Then:

```dart
await Mail.queue(message);

// send it in 10 minutes
await Mail.later(Duration(minutes: 10), message);

// another mailer and another queue
await Mail.mailer('ses').queue(message, queue: 'emails');
```

`queue()` and `later()` return the job id.

- The message is checked at once. A bad message fails in the request, not in the worker.
- The default from and reply-to addresses are added at once.
- The mailer name is saved with the job. The worker sends with the same mailer, so with the same transport.
- The worker starts the providers of your app, so your `MailProvider` and mail config are there too.
- The worker flags `--tries` and `--timeout` work for queued emails, like for other jobs.
- With the `sync` queue driver, the email is sent at once. `later()` does not wait.

| Option | Default | What it does |
| --- | --- | --- |
| `queue` | `default` | the queue name |
| `encrypt` | `false` | save the job data encrypted with the app key. The worker needs the same key |

> **The whole email is saved in the queue**
> The addresses, the subject, the body and every attachment are saved in Redis or in the `jobs` table.
> Attachments are saved as base64, so they take about 4/3 of their size.
> Keep attachments small, a few MB at most. MySQL and MariaDB refuse a job bigger than `max_allowed_packet` (by default 64 MB in MySQL 8, 16 MB in MariaDB). Redis keeps every job in memory.
> For a big file, write your own job. Save the file path or a storage key in the job, and build the email in `handle()`.

> **Encrypt personal data**
> An email has personal data. When other people can read Redis or the `jobs` table, use `encrypt: true`.

In tests, `Mail.fake()` catches queued emails too. They go to `mail.queued`, not to a job queue. So the test needs no queue:

```dart
ArrayTransport mail = Mail.fake();

await Mail.later(Duration(minutes: 10), message);
expect(mail.queued.single.delay, Duration(minutes: 10));
expect(mail.sent, isEmpty);
```

Each `QueuedMessage` has the `message`, the `mailer` name, the job `id`, the `delay`, the `queue` name and `encrypt`.

With both `Mail.fake()` and `Queue.fake()` (dox_queue) on, `Mail.fake()` catches the queued email first. It goes to `mail.queued`, and `Queue.fake()` does not see a job. To check the mail job with `Queue.fake()`, do not call `Mail.fake()`.

## Transports

### SMTP

```dart
'smtp': SmtpTransport(
  host: 'smtp.example.com',
  port: 587,
  username: Env.get('MAIL_USERNAME'),
  password: Env.get('MAIL_PASSWORD'),
  encryption: SmtpEncryption.starttls,
),
```

| Option | Default | What it does |
| --- | --- | --- |
| `host` | required | the server |
| `port` | 465 for `tls`, 587 for `starttls`, 25 for `none` | the port |
| `username`, `password` | none | the login. No username: no login |
| `encryption` | `starttls` | `none`, `starttls` (switch to TLS after connect) or `tls` (TLS from the start) |
| `allowInsecure` | `false` | accept a self-signed TLS certificate. Only for test servers |
| `auth` | PLAIN, or LOGIN when the server has no PLAIN | `SmtpAuth.plain`, `SmtpAuth.login` or `SmtpAuth.xoauth2` |
| `localDomain` | `localhost` | the name of this machine, for `EHLO` |
| `timeout` | 30 seconds | the time to connect, and to wait for each reply |
| `keepAlive` | `false` | keep the connection open for the next message |

With `starttls`, the send fails when the server does not offer STARTTLS. Your password is never sent in plain text by mistake.

For Gmail or Outlook with OAuth 2, use `auth: SmtpAuth.xoauth2`. The `username` is the email and the `password` is the access token.

`keepAlive: true` is good when you send many emails. One connection sends them one by one. When the server closed it, the next send opens a new one.

For local work, [Mailpit](https://mailpit.axllent.org) catches all emails:

```dart
'mailpit': SmtpTransport(
  host: 'localhost',
  port: 1025,
  encryption: SmtpEncryption.none,
),
```

### Amazon SES

There are two classes. Both send the same MIME message, with attachments and inline images.

- `SesTransport`: SES API v1, `SendRawEmail`.
- `SesV2Transport`: SES API v2, `SendEmail` with raw content.

```dart
'ses': SesV2Transport(
  key: Env.get('AWS_ACCESS_KEY_ID'),
  secret: Env.get('AWS_SECRET_ACCESS_KEY'),
  region: Env.get('AWS_REGION', 'us-east-1'),
),
```

| Option | Default | What it does |
| --- | --- | --- |
| `key` | required | the AWS access key id |
| `secret` | required | the AWS secret access key |
| `sessionToken` | none | for temporary keys, eg. from a role |
| `region` | `us-east-1` | the AWS region of SES |
| `configurationSet` | none | the SES configuration set, to track events |
| `endpoint` | `https://email.<region>.amazonaws.com/` | another API address, eg. a VPC endpoint or LocalStack |

The requests are signed with AWS Signature Version 4. No AWS SDK is needed.

### Azure Communication Services

```dart
'azure': AzureTransport(
  endpoint: 'https://my-app.europe.communication.azure.com',
  accessKey: Env.get('AZURE_EMAIL_KEY'),
),
```

Or with the connection string of the Azure portal:

```dart
'azure': AzureTransport.fromConnectionString(
  Env.get('AZURE_EMAIL_CONNECTION_STRING'),
),
```

| Option | Default | What it does |
| --- | --- | --- |
| `endpoint` | required | the address of your resource |
| `accessKey` | required | the access key of the resource |
| `apiVersion` | `2023-03-31` | the API version |
| `disableTracking` | `false` | turn off open and click tracking |

Requests are signed with the access key (HMAC-SHA256). Inline images need a newer `apiVersion` that supports them.

### Resend

```dart
'resend': ResendTransport(apiKey: Env.get('RESEND_API_KEY')),
```

### Mailgun

```dart
'mailgun': MailgunTransport(
  apiKey: Env.get('MAILGUN_API_KEY'),
  domain: 'mg.example.com',
  region: MailgunRegion.eu,
),
```

`region` is `MailgunRegion.us` (the default) or `MailgunRegion.eu`. Use the region of your Mailgun domain.

### Postmark

```dart
'postmark': PostmarkTransport(
  serverToken: Env.get('POSTMARK_TOKEN'),
  messageStream: 'outbound',
),
```

`messageStream` is optional. Without it, Postmark uses the default stream of the server.

### sendmail

Sends with the `sendmail` program of the server (Postfix, Exim, msmtp and others).

```dart
'sendmail': SendmailTransport(
  path: '/usr/sbin/sendmail',
  mode: SendmailMode.smtp,
),
```

| Mode | Command | How it works |
| --- | --- | --- |
| `SendmailMode.smtp` (default) | `sendmail -bs` | speaks SMTP on stdin and stdout |
| `SendmailMode.pipe` | `sendmail -t -i` | pipes the message in. sendmail reads the recipients from the headers |

### Log

Prints each email and sends nothing. Good for local work.

```dart
'log': LogTransport(),
```

Pass `output` to print somewhere else, eg. `LogTransport(output: stderr.writeln)` (from `dart:io`).

One option, off by default:

- `bothBodies: true` shows the text body and the HTML body when the email has both. When it is off, only the text body is shown.

```dart
'log': LogTransport(bothBodies: true),
```

### Array

Keeps each email in a list and sends nothing. See [Testing](#testing).

```dart
'array': ArrayTransport(),
```

### Failover

Tries each transport in order, until one sends the email. When every transport fails, it throws the error of the last one. To see why the first ones failed, pass `onError`. It gets the error of each transport that fails. When `onError` throws, the error is ignored and the next transport is still tried. An `async` `onError` is not awaited. A line break in an address, the subject or a header throws a `MailException` at once, and no transport tries it.

```dart
SesV2Transport ses = SesV2Transport(key: '...', secret: '...');
SmtpTransport smtp = SmtpTransport(host: 'smtp.example.com');

MailConfig mailConfig = MailConfig(
  defaultMailer: 'main',
  mailers: <String, Transport>{
    'main': FailoverTransport(<Transport>[ses, smtp]),
  },
);
```

## Tags and metadata

Each provider has its own way to group and mark emails. This is what each transport does with `tags` and `metadata`:

| Transport | `tags` | `metadata` |
| --- | --- | --- |
| SES | not used | message tags |
| Resend | tags with the value `true` | tags |
| Mailgun | `o:tag` | variables (`v:name`) |
| Postmark | the first tag | metadata |
| Azure, SMTP, sendmail | not used | not used |

For SMTP and sendmail, use `headers` instead.

## Hooks

Run code before or after each email is sent, eg. to log it. Dox has no event system, so hooks are plain functions.

Each isolate has its own hooks: the server isolates and the queue worker. So add them in `setup()` of your mail provider, after `super.setup()`. Then every isolate gets them. A hook added in `main()` does not reach queued emails.

```dart
class AppMailProvider extends MailProvider {
  AppMailProvider() : super(mailConfig);

  @override
  void setup() {
    super.setup();
    // hooks are kept in a list: clear it, so a second setup() in the
    // same isolate does not add each hook twice
    Mail.clearHooks();
    Mail.onSending((Message message) {
      print('sending "${message.subject}" to ${message.to}');
    });
    Mail.onSent((SentMessage sent) {
      print('sent ${sent.messageId}');
    });
  }
}
```

- Hooks run for every mailer. They also run for queued emails, when the worker sends them, and with `Mail.fake()`.
- When an `onSending` hook throws, the email is not sent. `send()` throws that error.
- When an `onSent` hook throws, the error is logged and `send()` does not throw. The email is already sent, so a queue worker does not send it again.
- `Mail.clearHooks()` removes all hooks, eg. in a test. Call it at the start of `setup()` too: when `setup()` runs twice in one isolate, each hook would run twice.

## Send all email to one address

On a staging server, send every email to your own inbox, so real users get nothing. Like hooks, call it in `setup()` of your mail provider, after `super.setup()`, so every isolate gets it:

```dart
class AppMailProvider extends MailProvider {
  AppMailProvider() : super(mailConfig);

  @override
  void setup() {
    super.setup();
    if (Env.get<String>('APP_ENV') == 'staging') {
      Mail.alwaysTo('qa@example.com');
    }
  }
}
```

The `to` of each email becomes that address, and `cc` and `bcc` are cleared. It counts for queued emails too. `Mail.alwaysTo(null)` turns it off.

## Testing

`Mail.fake()` sends every mailer to one `ArrayTransport`. Nothing goes out. Then check what was sent.

```dart
import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

void main() {
  late ArrayTransport mail;

  setUp(() {
    mail = Mail.fake();
  });

  tearDown(() {
    Mail.restore();
  });

  test('sign up sends a welcome email', () async {
    await signUp('ann@example.com');

    expect(mail.messages, hasLength(1));
    Message message = mail.messages.single;
    expect(message.to.single.email, 'ann@example.com');
    expect(message.subject, 'Welcome');
  });
}
```

`Mail.fake()` works with or without a config. Call it after the app has started, because `MailProvider` sets up the config again at start.

The fake has check methods. Each one throws a `StateError` when the check fails. The error text lists the subject and the to addresses of each email, so you see what was there.

```dart
mail.assertSent((Message m) => m.subject == 'Welcome');
mail.assertSentCount(1);
mail.assertNotSent((Message m) => m.to.any((Address a) => a.email == 'bob@example.com'));
mail.assertNothingQueued();
```

| Method | It checks that |
| --- | --- |
| `assertSent([test])` | an email was sent. With `test`, an email that `test` says yes to |
| `assertSentCount(count, [test])` | `count` emails were sent. With `test`, `count` emails that `test` says yes to |
| `assertNotSent(test)` | no email that `test` says yes to was sent |
| `assertNothingSent()` | no email was sent |
| `assertQueued([test])` | an email was queued. With `test`, an email that `test` says yes to |
| `assertNotQueued(test)` | no email that `test` says yes to was queued |
| `assertNothingQueued()` | no email was queued |

`test` gets the `Message`. For the delay or the queue name of a queued email, read `mail.queued`.

`mail.clear()` forgets the sent and the queued emails.

## Integration tests

These tests send real email to free test servers and read it back. They are in `test/integration/` and have the `integration` tag. With no servers, `dart test` skips them.

You need Docker. This starts the servers from `docker-compose.yaml` and runs the tests:

```bash
tool/integration_test.sh
```

| Server | Tests |
| --- | --- |
| Mailpit | SMTP: no TLS, STARTTLS, TLS, AUTH PLAIN and LOGIN, keepAlive. sendmail `-t -i` and `-bs` |
| LocalStack | SES v1 |
| moto | SES v1 and v2 |
| api.postmarkapp.com | Postmark, with the test token `POSTMARK_API_TEST` |

The servers keep running. Stop them with `docker compose down`.

## Your own transport

Extend `Transport` and add it to `mailers`:

```dart
class MyApiTransport extends Transport {
  @override
  Future<SentMessage> send(Message message) async {
    // call your API here
    return SentMessage(message, messageId: 'id from the API');
  }
}
```

The message is checked, and has a from address, when it gets to `send()` from `Mail.send()`. If you call your transport's `send()` yourself, call `message.check()` first.

For a provider that takes raw MIME, `MimeBuilder().build(message)` gives the MIME text.
