import 'dart:async';

import 'package:dox_core/utils/log_buffer.dart';
import 'package:dox_queue/dox_queue.dart';

/// One job of [MemoryQueueDriver].
class _Entry {
  _Entry(this.queue, this.text, this.attempts, this.availableAt);

  final String queue;
  final String text;
  final int attempts;
  final int availableAt;
}

/// A queue driver in memory, for the tests of queued mail. Only what a
/// worker needs: push, pop, delete, release, fail and failed.
class MemoryQueueDriver implements QueueDriver {
  final List<_Entry> _jobs = <_Entry>[];
  final List<FailedJob> _failed = <FailedJob>[];

  @override
  Future<void> push(
    JobPayload payload, {
    Duration delay = Duration.zero,
  }) async {
    _jobs.add(
      _Entry(
        payload.queue,
        payload.encode(),
        0,
        QueueDriver.now() + delay.inMilliseconds,
      ),
    );
  }

  @override
  Future<ReservedJob?> pop(String queue) async {
    int now = QueueDriver.now();
    for (_Entry entry in _jobs) {
      if (entry.queue != queue || entry.availableAt > now) continue;
      _jobs.remove(entry);
      return ReservedJob(
        JobPayload.decode(entry.text),
        attempts: entry.attempts + 1,
        ref: entry,
      );
    }
    return null;
  }

  @override
  Future<void> delete(ReservedJob job) async {}

  @override
  Future<void> release(ReservedJob job, Duration delay) async {
    _jobs.add(
      _Entry(
        job.payload.queue,
        job.payload.encode(),
        job.attempts,
        QueueDriver.now() + delay.inMilliseconds,
      ),
    );
  }

  @override
  Future<void> fail(ReservedJob job, String error) async {
    _failed.add(
      FailedJob(
        id: job.payload.id,
        queue: job.payload.queue,
        payload: job.payload.encode(),
        error: error,
        failedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<List<FailedJob>> failed() async => List<FailedJob>.of(_failed);

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Makes a new [MemoryQueueDriver] for `QueueConfig(driver: 'memory')`.
class MemoryQueueFactory implements QueueDriverFactory {
  @override
  QueueDriver create(QueueConfig config, {String? name}) {
    return MemoryQueueDriver();
  }
}

/// every line the Dox logger writes while [body] runs. The logger
/// writes through `LogBuffer.writer`, so catch the text there.
Future<String> logOf(FutureOr<void> Function() body) async {
  // older lines must not land in this log
  LogBuffer.flush();
  StringBuffer log = StringBuffer();
  void Function(String) old = LogBuffer.writer;
  LogBuffer.writer = log.write;
  try {
    await body();
    LogBuffer.flush();
  } finally {
    LogBuffer.writer = old;
  }
  return log.toString();
}
