/// Send email from the Dox framework: SMTP, Amazon SES, Azure, Resend,
/// Mailgun, Postmark and sendmail.
library;

export 'src/address.dart';
export 'src/attachment.dart';
export 'src/aws/sigv4.dart';
export 'src/mail.dart';
export 'src/mail_config.dart';
export 'src/mail_exception.dart';
export 'src/mail_service.dart';
export 'src/mailer.dart';
export 'src/message.dart';
export 'src/mime/mime_builder.dart';
export 'src/mime/mime_encoding.dart';
export 'src/transport.dart';
export 'src/transports/array_transport.dart';
export 'src/transports/azure_transport.dart';
export 'src/transports/failover_transport.dart';
export 'src/transports/http_transport.dart';
export 'src/transports/log_transport.dart';
export 'src/transports/mailgun_transport.dart';
export 'src/transports/postmark_transport.dart';
export 'src/transports/resend_transport.dart';
export 'src/transports/sendmail_transport.dart';
export 'src/transports/ses_transport.dart';
export 'src/transports/smtp_transport.dart';
