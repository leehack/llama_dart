import 'engine_generation_port.dart';
import 'engine_template_port.dart';
import 'engine_token_count_port.dart';

/// Narrow engine contract needed by chat-completion use cases.
abstract class ChatCompletionEnginePort
    implements EngineTemplatePort, EngineGenerationPort, EngineTokenCountPort {}
