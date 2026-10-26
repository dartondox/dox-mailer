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
