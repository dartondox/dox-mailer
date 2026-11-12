import 'package:dox_view/dox_view.dart';
import 'package:markdown/markdown.dart' as md;

import 'address.dart';
import 'attachment.dart';
import 'mail.dart';
import 'mailer.dart';
import 'message.dart';

/// One kind of email in its own class.
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
  ///
  /// Text values of [data] are not Markdown: `{{ name }}` with
  /// `[Verify](https://evil.com)` shows that text, not a link. This
  /// counts for text in maps, lists, sets and objects with `toJson()` too.
  /// To put Markdown from a value in the email, pass a `SafeString`.
  /// These characters of a text value stay text: backslash, backtick,
  /// `*`, `[`, `]`, `#` and `|`. A `_` is not changed, so `_word_` can
  /// still be italic. In `@if` and other code of the template, a value
  /// with one of these characters is not equal to the same text written
  /// in the template.
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
      String source = View.render(
        markdown,
        Map<String, Object?>.from(_maskData(data, 0)! as Map<Object?, Object?>),
      );
      html ??= layout(_unmask(_markdownHtml(source)));
      text ??= _unmask(_unescape(source));
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

/// A simple email made of lines and one button. No template needed.
/// ```
/// MailMessage(subject: 'Invoice paid')
///   ..line('We got your payment.')
///   ..action('View invoice', 'https://example.com/invoices/1')
///   ..line('Thank you!');
/// ```
/// Lines can use Markdown, like `**bold**`. HTML in them shows as
/// text. Links in them go through the same URL check as templates.
class MailMessage extends Mailable {
  MailMessage({
    this.subject = '',
    this.greeting = 'Hello!',
    this.salutation,
    this.to = const <Address>[],
    this.cc = const <Address>[],
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
  final List<Address> cc;

  @override
  final List<Attachment> attachments = <Attachment>[];

  @override
  final String? mailer;

  /// the lines and buttons: a button has a URL
  final List<(String, String?)> _items = <(String, String?)>[];

  bool _error = false;

  /// add a paragraph
  void line(String text) {
    _items.add((text, null));
  }

  /// add a file
  void attach(Attachment file) {
    attachments.add(file);
  }

  /// Make the buttons red, for a message about a problem.
  void error() {
    _error = true;
  }

  /// Add a button that opens [url]. Throws an [ArgumentError] for a
  /// URL with an unsafe scheme, like `javascript:` or `data:`. Only
  /// `http`, `https`, `mailto`, `tel`, `cid` and relative URLs work.
  void action(String label, String url) {
    // throw, not drop the href: a dead button would hide the mistake
    if (!_isSafeUrl(url)) {
      throw ArgumentError.value(url, 'url', 'is not a safe link');
    }
    _items.add((label, url));
  }

  /// the greeting, the body and the salutation. [html]: as Markdown
  List<String> _parts(bool html) {
    String? greeting = this.greeting;
    String? salutation = this.salutation;
    String button = _error ? 'button button-error' : 'button';
    return <String>[
      if (greeting != null)
        html
            ? _markdownHtml('**${_oneLine(greeting)}**', html: false)
            : greeting,
      for (final (String text, String? url) in _items)
        switch ((html, url)) {
          (true, null) => _markdownHtml(text, html: false),
          (false, null) => text,
          // a button is HTML, not Markdown: the label is plain text, so
          // a URL in it does not become a link inside the button
          (true, String url) =>
            '<p><a href="${escapeHtml(url)}" class="$button">'
                '${escapeHtml(text)}</a></p>\n',
          (false, String url) => '$text: $url',
        },
      if (salutation != null)
        html ? _markdownHtml(salutation, html: false) : salutation,
    ];
  }

  @override
  String get html => layout(_parts(true).join());

  @override
  String get text => _parts(false).join('\n\n');
}

/// The Markdown characters of a text value of `{{ }}`. While the
/// Markdown is parsed, each one is a private use character (U+E000 and
/// up), so it is plain text. [_unmask] puts them back after. `_` is not
/// in the list: it is in many keys and codes, like `in_progress`, that
/// a template compares.
const String _mdChars = r'\`*[]#|';

/// [value] with the text in it masked, see [_mdChars]. Maps, sets,
/// other iterables (as lists) and objects with `toJson()` are copied.
/// Other values stay as they are.
Object? _maskData(Object? value, int depth) {
  // ponytail: deep data is left as it is, so a map that holds itself
  // does not loop forever
  if (depth > 32) return value;
  switch (value) {
    case String text:
      return _mask(text);
    case Map<Object?, Object?> map:
      return <Object?, Object?>{
        for (MapEntry<Object?, Object?> e in map.entries)
          e.key: _maskData(e.value, depth + 1),
      };
    case Set<Object?> set:
      return <Object?>{for (Object? item in set) _maskData(item, depth + 1)};
    case Iterable<Object?> list:
      return <Object?>[for (Object? item in list) _maskData(item, depth + 1)];
    case null || num() || bool() || SafeString() || Function() || Record():
      return value;
  }
  // like dox_view: an object is read with its toJson()
  Object? json;
  try {
    json = (value as dynamic).toJson();
  } on NoSuchMethodError {
    return value;
  }
  return json is Map<Object?, Object?> ? _maskData(json, depth) : value;
}

String _mask(String text) {
  if (!text.contains(_mdChar)) return text;
  StringBuffer out = StringBuffer();
  for (int char in text.codeUnits) {
    int index = _mdChars.codeUnits.indexOf(char);
    out.writeCharCode(index < 0 ? char : 0xE000 + index);
  }
  return out.toString();
}

final RegExp _mdChar = RegExp(r'[\\`*\[\]#|]');

/// one masked character: U+E000 and up, one per char of [_mdChars]
final RegExp _masked = RegExp('[\uE000-\uE006]');

/// undo [_mask]
String _unmask(String text) {
  return text.replaceAllMapped(_masked, _unmaskChar);
}

String _unmaskChar(Match match) {
  return _mdChars[match[0]!.codeUnitAt(0) - 0xE000];
}

/// a masked character in a link: the Markdown parser writes it as UTF-8
/// in `%XX`, eg. U+E005 as `%EE%80%85`
final RegExp _maskedUrl = RegExp('%EE%80%8([0-6])', caseSensitive: false);

/// undo [_mask] in a URL
String _unmaskUrl(String url) {
  return _unmask(url).replaceAllMapped(_maskedUrl, _unmaskUrlChar);
}

String _unmaskUrlChar(Match match) => _mdChars[int.parse(match[1]!)];

/// [markdown] as HTML, with GitHub tables and lists. Links and images
/// with an unsafe scheme, like `javascript:` or `data:`, lose their URL.
/// Dox removes the unsafe URL itself.
///
/// It is CommonMark with tables. There are no GFM
/// autolinks: a bare URL stays text. Write `<url>` or `[text](url)`.
///
/// With [html] false, raw HTML shows as text, eg. for `MailMessage`
/// lines. Code spans still show `<br>` right.
String _markdownHtml(String markdown, {bool html = true}) {
  List<md.Node> nodes = md.Document(
    extensionSet: md.ExtensionSet.commonMark,
    blockSyntaxes: const <md.BlockSyntax>[md.TableSyntax()],
  ).parse(markdown);
  if (!html) _escapeRawHtml(nodes);
  if (html) _fixCodeEscape(nodes);
  _dropUnsafeUrls(nodes);
  return '${md.renderToHtml(nodes)}\n';
}

/// Shows raw HTML as text. package:markdown escapes `<` and `>` in
/// normal text and in code, so a text node with a `<` or a `>` is raw
/// HTML.
void _escapeRawHtml(List<md.Node>? nodes) {
  if (nodes == null) return;
  for (int i = 0; i < nodes.length; i++) {
    md.Node node = nodes[i];
    if (node is md.Element) {
      _escapeRawHtml(node.children);
    } else if (node is md.Text && node.text.contains(RegExp('[<>]'))) {
      nodes[i] = md.Text(
        node.text.replaceAll('<', '&lt;').replaceAll('>', '&gt;'),
      );
    }
  }
}

/// `{{ }}` escapes `<` as `&lt;`, and a code span escapes the `&` once
/// more, so `` `{{ tag }}` `` showed `&lt;b&gt;`. Undo the second escape
/// in code spans of a template.
void _fixCodeEscape(List<md.Node>? nodes) {
  for (md.Node node in nodes ?? const <md.Node>[]) {
    if (node is! md.Element) continue;
    List<md.Node>? children = node.children;
    if (node.tag == 'code' && children != null) {
      for (int i = 0; i < children.length; i++) {
        md.Node child = children[i];
        if (child is md.Text) {
          children[i] = md.Text(
            child.text.replaceAllMapped(_doubleEscape, _firstGroup),
          );
        }
      }
    } else {
      _fixCodeEscape(children);
    }
  }
}

final RegExp _doubleEscape = RegExp('&amp;(amp|lt|gt|quot|#39);');

String _firstGroup(Match match) => '&${match[1]};';

/// [text] on one line, so `**text**` stays one bold run
String _oneLine(String text) => text.replaceAll(RegExp(r'\s*\n\s*'), ' ');

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
      String? value = node.attributes[name];
      if (value == null) continue;
      // A `[x](url)` link comes decoded. An autolink comes escaped, and
      // `{{ url }}` adds one more escape. Decode until nothing changes,
      // check that URL, then escape it once: the renderer writes
      // attributes as they are. So the browser gets exactly the URL
      // that was checked, and `&#58;` can not turn into a `:` later.
      String? url = _decodeAll(value);
      if (url != null && _isSafeUrl(url)) {
        node.attributes[name] = escapeHtml(url);
      } else {
        node.attributes.remove(name);
      }
    }
    _fixAutolinkText(node);
    _dropUnsafeUrls(node.children);
  }
}

final RegExp _entity = RegExp(
  r'&(?:#(\d{1,7})|#[xX]([0-9a-fA-F]{1,6})|(amp|lt|gt|quot|apos));',
);

const Map<String, String> _named = <String, String>{
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
};

/// An autolink `<url>` shows its URL as its text, escaped one or two
/// times. Show it like the href: decoded, then escaped once.
void _fixAutolinkText(md.Element link) {
  List<md.Node>? children = link.children;
  String? href = link.attributes['href'];
  if (link.tag != 'a' || href == null || children == null) return;
  if (children.length != 1 || children.single is! md.Text) return;
  String? text = _decodeAll(children.single.textContent);
  if (text == null) return;
  String escaped = escapeHtml(text);
  // href is escaped once now. `<a@b.c>` gets `mailto:`
  for (String start in const <String>['', 'mailto:']) {
    if ('${escapeHtml(start)}$escaped' == href) {
      children[0] = md.Text(escaped);
      return;
    }
  }
}

/// [value] decoded with [_decodeEntities] until it does not change.
/// Null after 5 rounds: too deep to be a real URL.
String? _decodeAll(String value) {
  // a `{{ url }}` value is still masked here
  String current = _unmaskUrl(value);
  for (int round = 0; round < 5; round++) {
    String next = _decodeEntities(current);
    if (next == current) return current;
    current = next;
  }
  return null;
}

/// [url] with HTML entities decoded once, eg. `&amp;` and `&#58;`.
/// Other entities stay as text. That is safe: the result is checked
/// and then escaped, so the browser sees the same text.
String _decodeEntities(String url) {
  return url.contains('&') ? url.replaceAllMapped(_entity, _decode) : url;
}

String _decode(Match match) {
  String? named = match[3];
  if (named != null) return _named[named]!;
  String? decimal = match[1];
  int? code = decimal != null
      ? int.tryParse(decimal)
      : int.tryParse(match[2]!, radix: 16);
  if (code == null || code > 0x10FFFF) return match[0]!;
  return String.fromCharCode(code);
}

/// True for a relative URL or a URL with a scheme of [_safeSchemes].
/// Browsers skip spaces and control characters in a scheme, so they
/// are removed first.
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
a.button-error { background: #dc2626; }
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
