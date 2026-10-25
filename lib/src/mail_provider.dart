import 'package:dox_core/dox_core.dart';

import 'mail.dart';
import 'mail_config.dart';

/// Sets up the mailers in every isolate. Extend it in `lib/` so the
/// generated container finds it:
/// ```
/// class AppMailProvider extends MailProvider {
///   AppMailProvider() : super(mailConfig);
/// }
/// ```
class MailProvider extends DoxProvider {
  MailProvider(this.config);

  final MailConfig config;

  @override
  void setup() {
    Mail.configure(config);
  }

  /// closes open SMTP connections and HTTP clients
  @override
  Future<void> shutdown() async {
    await Mail.close();
  }
}
