## Unreleased

- Breaking: the queued mail classes `SendQueuedMail`, `SendEncryptedQueuedMail`, `RedactedMailError` and `QueueMailQueue` are now in dox_mailer. Import them from `package:dox_mailer/dox_mailer.dart`, not from dox_queue. The saved job names stay `dox_queue:SendQueuedMail` and `dox_queue:SendEncryptedQueuedMail`.
- Breaking: dox_mailer now depends on dox_queue.
- `Mail.mailQueue` falls back to `QueueMailQueue`, so `Mail.queue()` and `Mail.later()` use the dox_queue queue by default. There is no `StateError` when no queue was set. `Mail.useQueue(null)` goes back to it. The app needs the `QueueProvider` and a worker.
- `Mail.configure()` registers the mail jobs, so the worker can read them. So a `bin/queue.dart` worker needs `MailProvider` in its providers to run mail jobs, also the mail jobs that 3.1 saved. Without it the job fails with an unknown job name.
- Breaking: dox_mailer does not import `dox_core` any more. `dox_view` still uses it. `MailProvider` uses `DoxProvider` from `dox_annotation`.
- Breaking: the log transport always prints with `print`. `LogTransport(useLogger:)` is removed. An `onSent` hook error goes to `stderr`, not to the Dox `Logger`.
- Ships an AI agent skill (dox-mailer-guide). Install it in your app with `dart run skills@ get`.
- New: `LogTransport(bothBodies: true)` shows the text body and the HTML body when an email has both.
- Fix: when an `onSent` hook threw and the logger also threw an `Exception` (not an `Error`), `send()` failed after the email was sent. Now the error goes to stderr, and `send()` does not throw.
- Fix: when an `onSent` hook threw in a queue worker with `tries` above 1, the job failed after the email was sent. The worker then sent the email again. Now an `onSent` error is logged and `send()` does not throw. The other `onSent` hooks still run.
- Docs: start `setup()` with `Mail.clearHooks()`. Hooks are kept in a list, so when `setup()` runs twice in one isolate, each hook runs twice.

## 3.1.0

- Fix: in a Markdown mail, `{{ }}` escaped HTML but not Markdown. So a user value like `[Verify](https://evil.example)` became a real link. Now a text value of `data` stays text: backslash, backtick, `*`, `[`, `]`, `#` and `|` in it are not Markdown. This counts for text in maps, lists, sets and objects with `toJson()` too. To put Markdown from a value, pass a `SafeString`. In `@if`, a value with one of these characters is no longer equal to the same text written in the template.
- Fix: in a Markdown mail, `{{ tag }}` inside backticks was escaped twice, so `<b>` showed as `&lt;b&gt;`. Now it shows as `<b>`.
- Fix: in `FailoverTransport`, an `async` `onError` that throws gave an uncaught error. Now its error is ignored too. It is not awaited.
- New: `Mail.onSending()` and `Mail.onSent()` hooks run before and after each email is sent. `Mail.clearHooks()` removes them.
- New: `Mail.alwaysTo(address)` sends every email to one address, eg. on staging. `cc` and `bcc` are cleared. `Mail.alwaysTo(null)` turns it off.
- New: `Mail.raw(text, to: 'ann@example.com', subject: 'Hi')` sends a plain text email. `Mail.to('ann@example.com').cc(...).bcc(...).send(mailable)` adds recipients with chained calls. It also has `queue()`, `later()` and `raw()`. Addresses can be plain email text. `Address.list()` reads an `Address`, an email text, or a list of these.
- Docs: how to attach a file from a storage disk, with `Attachment(bytes, name)`.
- Fix: in `FailoverTransport`, an `onError` callback that throws stopped the failover, so the next transports were never tried. Now an error from `onError` is ignored: the next transport is still tried, and the send error is thrown as before.
- Fix: the `assertSentCount` error said "Expected 1 sent emails". Now it says "Expected 1 sent email".
- Docs: with both `Mail.fake()` and `Queue.fake()` on, `Mail.fake()` catches queued emails first.
- Fix: `Attachment.fromFile` read the file with a blocking call, which stops the server for every other request while it reads. Now the file is read without blocking when the message is sent or queued. A missing file now throws its `FileSystemException` from `send()` (or `queue()`), not from `fromFile`. Reading `bytes` before that still works: it reads the file then.
- With `Attachment.fromFile`, the file is read when the message is sent or queued, not when `fromFile` runs. A file that changed between `fromFile` and `send()` now sends the new content. A file that was deleted fails at `send()`.
- New: check methods on the `ArrayTransport` of `Mail.fake()`: `assertSent`, `assertSentCount`, `assertNotSent`, `assertNothingSent`, `assertQueued`, `assertNotQueued` and `assertNothingQueued`. Each one can take a test function that gets the `Message`. A failed check throws a `StateError` that lists the emails.
- New: `Mail.fake()` catches `Mail.queue()` and `Mail.later()` too, also the `queue()` and `later()` of mailables and queued notifications. The email goes to the new `queued` list of the `ArrayTransport`, as a `QueuedMessage` with the mailer name, the delay, the queue name and `encrypt`. No job is pushed, so a test needs no queue.
- New: mailables. A `Mailable` is one kind of email in its own class: `to`, `subject`, `view`, `data`, `attachments` and more. Send it with `send()`, or put it on the queue with `queue()` and `later()`. The body can come from a dox_view template (`view`, `textView`) or from plain text (`html`, `text`).
- New: Markdown mail. The `markdown` getter of a mailable names a dox_view template with Markdown. The HTML body is the Markdown inside a simple layout (override `layout()` for your own). The text body is the Markdown. The Markdown is CommonMark with tables, like Laravel mail, so a bare URL stays text: write `<url>` or `[text](url)`. Links and images with an unsafe URL (like `javascript:` or `data:`) lose their URL. Only `http`, `https`, `mailto`, `tel`, `cid` and relative URLs are kept.
- New: `MailMessage`, a mailable made of lines and a button, with no template. It also has `cc`, `attach()` and `error()` (red buttons). `action()` throws an `ArgumentError` for an unsafe URL, like `javascript:`.
- New: notifications. A `Notification` picks its channels in `via()`. `MailChannel` sends the `toMail()` email, or queues it when `shouldQueue` is true (with the `queue`, `delay` and `encrypt` getters). The mail route can be an `Address`, an email text, or a list of these. Add `Notifiable` to the user class and call `user.notify(notification)`, or `Notification.send(users, notification)`. Write your own channel (eg. a database channel) with `NotificationChannel` and `toArray()`. When a channel fails, `Notification.send()` still sends to the others, then throws a `NotificationException` with every error. With one notifiable and one error (like `user.notify()`), it throws that error as it is.
- dox_mailer now uses dox_view and markdown.
- New: `Mail.queue(message)` and `Mail.later(delay, message)`. They put the email on the job queue, so the request does not wait. A queue worker sends it later. `Mail.mailer('ses').queue()` and `.later()` keep the mailer, so the worker uses the same transport. Options: `queue` (the queue name) and `encrypt` (save the job data encrypted). The message is checked when it is queued. This needs dox_queue, which sets the queue in `Queue.configure()`.
- New: `Message.toJson()` and `Message.fromJson()`, also on `Address` and `Attachment`. Attachments are saved as base64.
- New: the `MailQueue` interface and `Mail.useQueue()`, so a queue package (or a test) can take queued emails.

## 3.0.0

- The first stable release.

## 3.0.0-rc.1

- Docs: README and `docs/mail.md` now say "provider", not "service", for `MailProvider`.

## 3.0.0-alpha.2

- `MailProvider` (was a DoxService): extend it in your app, `shutdown()` is optional.

## 3.0.0-alpha.1

- First version.
- `Mail.send()` and `Mail.mailer('name').send()`, with a default mailer and named mailers in `MailConfig`.
- `Message` with from, to, cc, bcc, reply-to, subject, text, HTML, attachments, inline images, custom headers, tags and metadata.
- Transports: SMTP, Amazon SES (v1 and v2 API), Azure Communication Services, Resend, Mailgun, Postmark, sendmail, log, array (for tests) and failover.
- One MIME builder for SMTP, SES and sendmail.
- AWS Signature Version 4, with no AWS SDK.
- `MailService` sets up the mailers in every isolate. `Mail.fake()` for tests.
