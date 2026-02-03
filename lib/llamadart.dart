/// High-performance Dart and Flutter plugin for llama.cpp.
///
/// **llamadart** allows you to run Large Language Models (LLMs) locally using
/// GGUF models across all major platforms (Android, iOS, macOS, Linux, Windows, Web).
///
/// ### Core Components
///
/// * [LlamaEngine]: The low-level orchestrator for model loading, tokenization,
///   and raw inference.
/// * [ChatSession]: A high-level, stateful interface for chat-based interactions.
///   It automatically manages conversation history and context window limits.
/// * [LlamaBackend]: The platform-agnostic interface for inference. Most users
///   should use the default [LlamaBackend()] factory, which automatically
///   selects the appropriate implementation (Native or Web).
///
/// ### Simple Example
///
/// ```dart
/// final engine = LlamaEngine(LlamaBackend());
/// await engine.loadModel('path/to/model.gguf');
///
/// final session = ChatSession(engine);
/// await for (final token in session.chat('Hello, how are you?')) {
///   stdout.write(token);
/// }
///
/// await engine.dispose();
/// ```
library;

// Models
export 'src/models/model_params.dart';
export 'src/models/generation_params.dart';
export 'src/models/llama_chat_message.dart';
export 'src/models/llama_content_part.dart';
export 'src/models/llama_chat_role.dart';
export 'src/models/llama_chat_template_result.dart';
export 'src/models/llama_log_level.dart';
export 'src/models/gpu_backend.dart';
export 'src/models/lora_adapter_config.dart';

// Tools - Typed tool definitions for function calling
export 'src/tools/tool_param.dart';
export 'src/tools/tool_params.dart';
export 'src/tools/tool_definition.dart';
export 'src/tools/tool_registry.dart';

// Engine
export 'src/engine/llama_engine.dart';
export 'src/engine/llama_tokenizer.dart';
export 'src/engine/chat_template_processor.dart';
export 'src/engine/chat_session.dart';

// Backends - User only needs the interface and the factory hidden within it.
// Internal classes like NativeLlamaBackend are hidden to prevent accidental misuse.
export 'src/backend/llama_backend_interface.dart';

// Common
export 'src/common/exceptions.dart';

// Bindings - Primary entry point for native symbols.
// Web builds get the stub to avoid dart:ffi issues.
export 'src/generated/llama_bindings.dart'
    if (dart.library.js_interop) 'src/generated/llama_bindings_stub.dart';
