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
  /// dox_queue) and does not send it at once. Only the mail channel
  /// reads it. Your own channels run at once.
  bool get shouldQueue => false;

  // The next three are used only when [shouldQueue] is true.

  /// The queue name of a queued email. Null: the default queue.
  String? get queue => null;

  /// The worker sends a queued email after this wait. Null: no wait.
  Duration? get delay => null;

  /// Save the queued email encrypted with the app key.
  bool get encrypt => false;

  /// Sends [notification] to each of [notifiables], on each channel.
  ///
  /// When a channel throws, the other channels and notifiables still
  /// get it. At the end, a [NotificationException] lists every error.
  /// With one notifiable and one error, that error is thrown as it is,
  /// so `on MailException` still works for `user.notify()`.
  static Future<void> send(
    Iterable<Object> notifiables,
    Notification notification,
  ) async {
    List<NotificationError> errors = <NotificationError>[];
    int count = 0;
    for (Object notifiable in notifiables) {
      count++;
      List<NotificationChannel> channels;
      try {
        channels = notification.via(notifiable);
      } catch (error, stack) {
        errors.add(NotificationError(notifiable, null, error, stack));
        continue;
      }
      for (NotificationChannel channel in channels) {
        try {
          await channel.send(notifiable, notification);
        } catch (error, stack) {
          errors.add(NotificationError(notifiable, channel, error, stack));
        }
      }
    }
    if (errors.length == 1 && count == 1) {
      Error.throwWithStackTrace(errors.single.error, errors.single.stack);
    }
    if (errors.isNotEmpty) throw NotificationException(errors);
  }
}

/// One failed send of `Notification.send()`.
class NotificationError {
  const NotificationError(
    this.notifiable,
    this.channel,
    this.error,
    this.stack,
  );

  final Object notifiable;

  /// the channel that failed. Null: `via()` failed.
  final NotificationChannel? channel;
  final Object error;
  final StackTrace stack;
}

/// Thrown by `Notification.send()` after it tried every notifiable and
/// every channel, when one or more of them failed.
class NotificationException implements Exception {
  NotificationException(this.errors);

  final List<NotificationError> errors;

  @override
  String toString() {
    StringBuffer out = StringBuffer(
      'NotificationException: ${errors.length} failed',
    );
    for (NotificationError e in errors) {
      String channel = e.channel?.runtimeType.toString() ?? 'via()';
      out.write('\n- ${_label(e.notifiable)} on $channel: ${e.error}');
    }
    return out.toString();
  }

  /// The type and the mail route of a [Notifiable], eg. `User
  /// (ann@example.com)`, because a model has no useful `toString()`.
  static String _label(Object notifiable) {
    if (notifiable is! Notifiable) return '$notifiable';
    try {
      Object? route = notifiable.routeNotificationFor('mail');
      if (route != null) return '${notifiable.runtimeType} ($route)';
    } catch (_) {
      // the route itself failed: the type alone
    }
    return '${notifiable.runtimeType}';
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
    Duration? delay = notification.delay;
    if (notification.shouldQueue && delay != null) {
      await mailer.later(
        delay,
        message,
        queue: notification.queue,
        encrypt: notification.encrypt,
      );
    } else if (notification.shouldQueue) {
      await mailer.queue(
        message,
        queue: notification.queue,
        encrypt: notification.encrypt,
      );
    } else {
      await mailer.send(message);
    }
  }

  static List<Address> _route(Object notifiable) {
    Object? route = notifiable is Notifiable
        ? notifiable.routeNotificationFor('mail')
        : notifiable;
    return switch (route) {
      List<Object?> list => <Address>[
        for (Object? item in list) _address(notifiable, item),
      ],
      _ => <Address>[_address(notifiable, route)],
    };
  }

  /// [item] of a mail route: an [Address] or an email text
  static Address _address(Object notifiable, Object? item) {
    return switch (item) {
      Address address => address,
      String email => Address.parse(email),
      _ => throw MailException(
        '${notifiable.runtimeType} has no mail address. Give it '
        'routeNotificationFor(\'mail\') or set `to` in toMail()',
      ),
    };
  }
}
