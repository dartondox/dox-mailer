import 'mail_exception.dart';

/// An email address with an optional name.
/// ```
/// Address('ann@example.com')
/// Address('ann@example.com', 'Ann Lee')
/// Address.parse('Ann Lee <ann@example.com>')
/// ```
class Address {
  const Address(this.email, [this.name]);

  /// Reads `ann@example.com` or `Ann Lee <ann@example.com>`.
  factory Address.parse(String text) {
    String value = text.trim();
    int open = value.lastIndexOf('<');
    if (open >= 0 && value.endsWith('>')) {
      String name = value.substring(0, open).trim();
      if (name.length >= 2 && name.startsWith('"') && name.endsWith('"')) {
        name = name.substring(1, name.length - 1);
      }
      String email = value.substring(open + 1, value.length - 1).trim();
      return Address(email, name.isEmpty ? null : name);
    }
    return Address(value);
  }

  final String email;
  final String? name;

  /// Throws a [MailException] when the address can not be used in a mail
  /// header, eg. it has no `@` or has a line break.
  void check() {
    if (!email.contains('@') || RegExp(r'[\s<>,;]').hasMatch(email)) {
      throw MailException('"$email" is not a valid email address');
    }
    if (name != null && RegExp(r'[\r\n]').hasMatch(name!)) {
      throw MailException('the name of "$email" has a line break');
    }
  }

  /// `Ann Lee <ann@example.com>`, or the email alone when there is no
  /// name. The name is not encoded: use it for logs and JSON APIs.
  @override
  String toString() {
    String? text = name;
    if (text == null || text.isEmpty) return email;
    if (RegExp(r'[()<>\[\]:;@\\,."]').hasMatch(text)) {
      text = '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
    }
    return '$text <$email>';
  }

  @override
  bool operator ==(Object other) =>
      other is Address && other.email == email && other.name == name;

  @override
  int get hashCode => Object.hash(email, name);
}
