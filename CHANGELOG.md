## Unreleased

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
