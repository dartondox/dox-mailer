import '../message.dart';
import '../transport.dart';

/// Keeps every message in [sent] and sends nothing. For tests.
/// `Mail.fake()` uses it.
class ArrayTransport extends Transport {
  final List<SentMessage> sent = <SentMessage>[];

  /// the sent messages
  List<Message> get messages => sent.map((SentMessage s) => s.message).toList();

  @override
  Future<SentMessage> send(Message message) async {
    SentMessage result = SentMessage(
      message,
      messageId: 'array-${sent.length + 1}',
    );
    sent.add(result);
    return result;
  }

  /// forget the sent messages
  void clear() => sent.clear();
}
