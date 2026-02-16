import 'chat_completion_engine_port.dart';
import 'engine_cancellation_port.dart';
import 'engine_readiness_port.dart';

/// Full engine contract used by HTTP API composition.
abstract class ApiServerEngine
    implements
        EngineReadinessPort,
        EngineCancellationPort,
        ChatCompletionEnginePort {}
