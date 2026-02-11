import 'package:test/test.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';

void main() {
  group('LlamaLogger', () {
    late LlamaLogger logger;

    setUp(() {
      logger = LlamaLogger.instance;
      logger.setLevel(LlamaLogLevel.none);
      logger.setHandler(null);
    });

    test('singleton instance is persistent', () {
      expect(LlamaLogger.instance, same(LlamaLogger.instance));
    });

    test('respects log level filtering', () {
      final logs = <LlamaLogRecord>[];
      logger.setHandler((record) => logs.add(record));

      logger.setLevel(LlamaLogLevel.warn);

      logger.debug('debug message');
      logger.info('info message');
      logger.warn('warn message');
      logger.error('error message');

      expect(logs.length, 2);
      expect(logs[0].level, LlamaLogLevel.warn);
      expect(logs[0].message, 'warn message');
      expect(logs[1].level, LlamaLogLevel.error);
      expect(logs[1].message, 'error message');
    });

    test('custom handler receives log records', () {
      LlamaLogRecord? receivedRecord;
      logger.setHandler((record) => receivedRecord = record);
      logger.setLevel(LlamaLogLevel.info);

      final now = DateTime.now();
      logger.info('test info');

      expect(receivedRecord, isNotNull);
      expect(receivedRecord!.level, LlamaLogLevel.info);
      expect(receivedRecord!.message, 'test info');
      expect(
        receivedRecord!.time.isAfter(now) ||
            receivedRecord!.time.isAtSameMomentAs(now),
        isTrue,
      );
    });

    test('error and stacktrace are preserved', () {
      LlamaLogRecord? receivedRecord;
      logger.setHandler((record) => receivedRecord = record);
      logger.setLevel(LlamaLogLevel.error);

      final error = Exception('test error');
      final stackTrace = StackTrace.current;

      logger.error('error with details', error, stackTrace);

      expect(receivedRecord!.error, error);
      expect(receivedRecord!.stackTrace, stackTrace);
    });

    test('level none suppresses all logs', () {
      final logs = <LlamaLogRecord>[];
      logger.setHandler((record) => logs.add(record));
      logger.setLevel(LlamaLogLevel.none);

      logger.error('this should not be logged');

      expect(logs, isEmpty);
    });

    test('LlamaLogRecord.toString() format', () {
      final record = LlamaLogRecord(
        level: LlamaLogLevel.info,
        message: 'test message',
        time: DateTime(2024, 1, 1, 12, 0, 0),
      );

      final str = record.toString();
      expect(str, contains('[INFO]'));
      expect(str, contains('test message'));
      expect(str, contains('2024-01-01T12:00:00.000'));
    });
  });
}
