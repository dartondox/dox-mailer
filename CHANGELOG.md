## Unreleased

- New: mailables. A `Mailable` is one kind of email in its own class: `to`, `subject`, `view`, `data`, `attachments` and more. Send it with `send()`, or put it on the queue with `queue()` and `later()`. The body can come from a dox_view template (`view`, `textView`) or from plain text (`html`, `text`).
- New: Markdown mail. The `markdown` getter of a mailable names a dox_view template with Markdown. The HTML body is the Markdown inside a simple layout (override `layout()` for your own). The text body is the Markdown. Links and images with an unsafe URL (like `javascript:` or `data:`) lose their URL. Only `http`, `https`, `mailto`, `tel`, `cid` and relative URLs are kept.
- New: `MailMessage`, a mailable made of lines and a button, with no template. `action()` throws an `ArgumentError` for an unsafe URL, like `javascript:`.
- New: notifications. A `Notification` picks its channels in `via()`. `MailChannel` sends the `toMail()` email, or queues it when `shouldQueue` is true (with the `queue`, `delay` and `encrypt` getters). The mail route can be an `Address`, an email text, or a list of these. Add `Notifiable` to the user class and call `user.notify(notification)`, or `Notification.send(users, notification)`. Write your own channel (eg. a database channel) with `NotificationChannel` and `toArray()`. When a channel fails, `Notification.send()` still sends to the others, then throws a `NotificationException` with every error.
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
