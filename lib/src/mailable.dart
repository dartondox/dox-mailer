import 'package:dox_view/dox_view.dart';
import 'package:markdown/markdown.dart' as md;

import 'address.dart';
import 'attachment.dart';
import 'mail.dart';
import 'mailer.dart';
import 'message.dart';

/// One kind of email in its own class, like a Laravel mailable.
/// Override the getters you need. The body comes from [html] and
/// [text], from the dox_view templates [view] and [textView], or from
/// the Markdown template [markdown].
/// ```
/// class WelcomeMail extends Mailable {
///   WelcomeMail(this.user);
///
///   final User user;
///
///   @override
///   List<Address> get to => <Address>[Address(user.email, user.name)];
///
///   @override
///   String get subject => 'Welcome';
///
///   @override
///   String? get markdown => 'emails/welcome';
///
///   @override
///   Map<String, Object?> get data => <String, Object?>{'name': user.name};
/// }
///
/// await WelcomeMail(user).send();
/// await WelcomeMail(user).queue();
/// ```
abstract class Mailable {
  const Mailable();

  List<Address> get to => const <Address>[];
  List<Address> get cc => const <Address>[];
  List<Address> get bcc => const <Address>[];
  List<Address> get replyTo => const <Address>[];

  /// Null: the `from` of the mail config.
  Address? get from => null;

  String get subject;

  /// the HTML body, when there is no template
  String? get html => null;

  /// the plain text body, when there is no template
  String? get text => null;

  /// A dox_view template for the HTML body, eg. `emails/welcome`.
  String? get view => null;

  /// A dox_view template for the plain text body. `{{ }}` escapes HTML,
  /// so the text is unescaped after the render.
  String? get textView => null;

  /// A dox_view template with Markdown, eg. `emails/welcome` for
  /// `resources/views/emails/welcome.dox.html`. The HTML body is the
  /// Markdown as HTML inside [layout]. The text body is the Markdown.
  String? get markdown => null;

  /// the variables of the templates
  Map<String, Object?> get data => const <String, Object?>{};

  List<Attachment> get attachments => const <Attachment>[];

  /// The mailer name of the mail config, eg. `ses`. Null: the default.
  String? get mailer => null;

  /// The HTML page around a Markdown body. Override it to use your own
  /// look, eg. in a base class of your mailables.
  String layout(String body) => markdownLayout(body);

  /// The email as a [Message]. Override it to set more, eg. headers:
  /// `super.toMessage().copyWith(headers: ...)`.
  Message toMessage() {
    String? html = this.html;
    String? text = this.text;
    String? view = this.view;
    String? textView = this.textView;
    String? markdown = this.markdown;
    if (view != null) html = View.render(view, data);
    if (textView != null) text = _unescape(View.render(textView, data));
    if (markdown != null) {
      String source = View.render(markdown, data);
      html ??= layout(_markdownHtml(source));
      text ??= _unescape(source);
    }
    return Message(
      from: from,
      to: to,
      cc: cc,
      bcc: bcc,
      replyTo: replyTo,
      subject: subject,
      html: html,
      text: text,
      attachments: attachments,
    );
  }

  /// Sends the email with [mailer].
  Future<SentMessage> send() => _mailer.send(toMessage());

  /// Puts the email on the job queue, see [Mail.queue]. The templates
  /// are rendered now, so the worker sends the finished email.
  Future<String> queue({String? queue, bool encrypt = false}) {
    return _mailer.queue(toMessage(), queue: queue, encrypt: encrypt);
  }

  /// Like [queue], but the worker sends it after [delay].
  Future<String> later(Duration delay, {String? queue, bool encrypt = false}) {
    return _mailer.later(delay, toMessage(), queue: queue, encrypt: encrypt);
  }

  Mailer get _mailer => Mail.mailer(mailer);
}

/// A simple email made of lines and one button, like the `MailMessage`
/// of Laravel notifications. No template needed.
/// ```
/// MailMessage(subject: 'Invoice paid')
///   ..line('We got your payment.')
///   ..action('View invoice', 'https://example.com/invoices/1')
///   ..line('Thank you!');
/// ```
/// Lines can use Markdown, like `**bold**`. HTML in them is escaped.
class MailMessage extends Mailable {
  MailMessage({
    this.subject = '',
    this.greeting = 'Hello!',
    this.salutation,
    this.to = const <Address>[],
    this.mailer,
  });

  @override
  final String subject;

  /// the first line, in bold. Null: none.
  final String? greeting;

  /// the last line, eg. `Regards, the Acme team`. Null: none.
  final String? salutation;

  /// Empty: a notification sends it to the address of the notifiable.
  @override
  final List<Address> to;

  @override
  final String? mailer;

  final List<String> _markdown = <String>[];
  final List<String> _text = <String>[];

  /// add a paragraph
  void line(String text) {
    _markdown.add(escapeHtml(text));
    _text.add(text);
  }

  /// add a button that opens [url]
  void action(String label, String url) {
    _markdown.add(
      '<a href="${escapeHtml(url)}" class="button">${escapeHtml(label)}</a>',
    );
    _text.add('$label: $url');
  }

  /// the greeting, the body and the salutation. [html]: as Markdown
  List<String> _parts(bool html) {
    String? greeting = this.greeting;
    String? salutation = this.salutation;
    return <String>[
      if (greeting != null) html ? '**${escapeHtml(greeting)}**' : greeting,
      ...(html ? _markdown : _text),
      if (salutation != null) html ? escapeHtml(salutation) : salutation,
    ];
  }

  @override
  String get html => layout(_markdownHtml(_parts(true).join('\n\n')));

  @override
  String get text => _parts(false).join('\n\n');
}

/// [markdown] as HTML, with GitHub tables and lists. Links and images
/// with an unsafe scheme, like `javascript:` or `data:`, lose their URL.
/// Laravel does the same (`allow_unsafe_links` is off).
String _markdownHtml(String markdown) {
  List<md.Node> nodes = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
  ).parse(markdown);
  _dropUnsafeUrls(nodes);
  return '${md.renderToHtml(nodes)}\n';
}

/// the schemes a link or an image of a Markdown email may use
const Set<String> _safeSchemes = <String>{
  'http',
  'https',
  'mailto',
  'tel',
  'cid',
};

void _dropUnsafeUrls(List<md.Node>? nodes) {
  for (md.Node node in nodes ?? const <md.Node>[]) {
    if (node is! md.Element) continue;
    for (String name in const <String>['href', 'src']) {
      String? url = node.attributes[name];
      if (url == null) continue;
      if (_isSafeUrl(url)) {
        // the renderer writes `&` as it is, so `&#58;` would turn into
        // a `:` in the browser. Escape it: the browser sees the text.
        node.attributes[name] = url.replaceAll('&', '&amp;');
      } else {
        node.attributes.remove(name);
      }
    }
    _dropUnsafeUrls(node.children);
  }
}

/// True for a relative URL or a URL with a scheme of [_safeSchemes].
/// Browsers skip spaces and control characters in a scheme, so they
/// are removed first. package:markdown has decoded entities already.
bool _isSafeUrl(String url) {
  String value = String.fromCharCodes(url.codeUnits.where(_isVisible))
      .toLowerCase();
  int colon = value.indexOf(':');
  if (colon < 0) return true;
  String scheme = value.substring(0, colon);
  // a colon after the path start, like `/a:b` or `?x=a:b`, is no scheme
  if (scheme.contains(RegExp(r'[/?#]'))) return true;
  return _safeSchemes.contains(scheme);
}

bool _isVisible(int char) => char > 0x20;

/// The default page around a Markdown email body: a white card on a
/// grey page, and `<a class="button">` as a button. Email apps do not
/// all read `<style>`, so it keeps to simple CSS.
String markdownLayout(String body) {
  return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body { margin: 0; padding: 24px 12px; background: #f4f4f7; color: #333; font: 16px/1.5 -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
.card { max-width: 570px; margin: 0 auto; padding: 32px; background: #fff; border-radius: 4px; }
a { color: #2563eb; }
a.button { display: inline-block; padding: 10px 18px; background: #2563eb; color: #fff; text-decoration: none; border-radius: 4px; }
table { border-collapse: collapse; } th, td { padding: 6px 10px; border-bottom: 1px solid #e5e5e5; text-align: left; }
</style>
</head>
<body><div class="card">
$body
</div></body>
</html>
''';
}

/// undo `escapeHtml`, for the text body of a template
String _unescape(String text) {
  if (!text.contains('&')) return text;
  return text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
}
