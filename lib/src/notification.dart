import 'address.dart';
import 'mail.dart';
import 'mail_exception.dart';
import 'mailable.dart';
import 'mailer.dart';
import 'message.dart';

/// A message to a user (a notifiable) over one or more channels, like a
/// Laravel notification. [via] picks the channels.
/// ```
/// class InvoicePaid extends Notification {
///   InvoicePaid(this.invoiceId);
///
///   final int invoiceId;
///
///   @override
///   List<NotificationChannel> via(Object notifiable) =>
///       <NotificationChannel>[const MailChannel()];
///
///   @override
///   Mailable toMail(Object notifiable) {
///     return MailMessage(subject: 'Invoice paid')
///       ..line('We got your payment.')
///       ..action('View invoice', 'https://example.com/invoices/$invoiceId');
///   }
/// }
///
/// await user.notify(InvoicePaid(1));
/// await Notification.send(users, InvoicePaid(1));
/// ```
abstract class Notification {
  const Notification();

  /// the channels that send this notification to [notifiable]
  List<NotificationChannel> via(Object notifiable);

  /// The email of [MailChannel]. With no `to` address, it goes to the
  /// mail route of the notifiable.
  Mailable toMail(Object notifiable) {
    throw UnimplementedError('$runtimeType has no toMail()');
  }

  /// The notification as data, for your own channels, eg. a database
  /// or a broadcast channel.
  Map<String, Object?> toArray(Object notifiable) => const <String, Object?>{};

  /// True: [MailChannel] puts the email on the job queue (needs
  /// dox_queue) and does not send it at once.
  bool get shouldQueue => false;

  /// Sends [notification] to each of [notifiables], on each channel.
  static Future<void> send(
    Iterable<Object> notifiables,
    Notification notification,
  ) async {
    for (Object notifiable in notifiables) {
      for (NotificationChannel channel in notification.via(notifiable)) {
        await channel.send(notifiable, notification);
      }
    }
  }
}

/// A way to send a [Notification], eg. mail, a database table or SMS.
abstract interface class NotificationChannel {
  Future<void> send(Object notifiable, Notification notification);
}

/// Add it to a class that gets notifications, eg. the user model.
/// ```
/// class User extends Model<User> with Notifiable {
///   @override
///   Object? routeNotificationFor(String channel) {
///     return channel == 'mail' ? Address(email!, name) : null;
///   }
/// }
/// ```
mixin Notifiable {
  /// Where [channel] sends to, eg. an [Address] (or an email text) for
  /// `mail`. Null: the channel has no address.
  Object? routeNotificationFor(String channel) => null;

  /// Sends [notification] to this notifiable.
  Future<void> notify(Notification notification) {
    return Notification.send(<Object>[this], notification);
  }
}

/// Sends the [Notification.toMail] email.
///
/// The address is the `to` of the email. With none, it is the mail
/// route of the notifiable: `routeNotificationFor('mail')` of a
/// [Notifiable], or the notifiable itself when it is an [Address] or an
/// email text. So `Notification.send([Address('ann@example.com')], n)`
/// works without a user.
class MailChannel implements NotificationChannel {
  const MailChannel();

  @override
  Future<void> send(Object notifiable, Notification notification) async {
    Mailable mail = notification.toMail(notifiable);
    Message message = mail.toMessage();
    if (message.to.isEmpty) {
      message = message.copyWith(to: _route(notifiable));
    }
    Mailer mailer = Mail.mailer(mail.mailer);
    if (notification.shouldQueue) {
      await mailer.queue(message);
    } else {
      await mailer.send(message);
    }
  }

  static List<Address> _route(Object notifiable) {
    Object? route = notifiable is Notifiable
        ? notifiable.routeNotificationFor('mail')
        : notifiable;
    return switch (route) {
      Address address => <Address>[address],
      String email => <Address>[Address.parse(email)],
      List<Address> list => list,
      _ => throw MailException(
        '${notifiable.runtimeType} has no mail address. Give it '
        'routeNotificationFor(\'mail\') or set `to` in toMail()',
      ),
    };
  }
}
