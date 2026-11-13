import 'dart:async';
import 'dart:io';

import 'package:dox_mailer/dox_mailer.dart';
import 'package:test/test.dart';

/// a stderr that keeps the text
class _Stderr implements Stdout {
  final StringBuffer text = StringBuffer();

  @override
  void writeln([Object? object = '']) => text.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('stderr.${invocation.memberName} is not faked');
  }
}

/// a stderr that always fails, like a closed pipe
class _BrokenStderr implements Stdout {
  @override
  void writeln([Object? object = '']) => throw const FormatException('closed');

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('stderr.${invocation.memberName} is not faked');
  }
}

void _throwingHook(SentMessage sent) => throw StateError('hook failed');

Future<SentMessage> _send() {
  return Mail.send(
    Message(
      to: const <Address>[Address('ann@example.com')],
      subject: 'Hi',
      text: 'Hello',
    ),
  );
}

ArrayTransport _setUp() {
  ArrayTransport main = ArrayTransport();
  Mail.configure(
    MailConfig(
      defaultMailer: 'main',
      from: const Address('app@example.com'),
      mailers: <String, Transport>{'main': main},
    ),
  );
  Mail.onSent(_throwingHook);
  addTearDown(Mail.clearHooks);
  return main;
}

void main() {
  test(
    'an onSent hook error goes to stderr and send() does not throw',
    () async {
      ArrayTransport main = _setUp();
      _Stderr err = _Stderr();
      SentMessage sent = await IOOverrides.runZoned(_send, stderr: () => err);
      expect(main.sent.single.messageId, sent.messageId);
      expect(err.text.toString(), contains('hook failed'));
    },
  );

  test('a broken stderr does not make send() throw', () async {
    ArrayTransport main = _setUp();
    SentMessage sent = await IOOverrides.runZoned(
      _send,
      stderr: _BrokenStderr.new,
    );
    expect(main.sent.single.messageId, sent.messageId);
  });
}
