/// High-performance Dart and Flutter plugin for llama.cpp.
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
export 'src/models/llama_tool.dart';

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
export 'src/common/json_schema_to_gbnf.dart';

// Bindings - Primary entry point for native symbols.
// Web builds get the stub to avoid dart:ffi issues.
export 'src/generated/llama_bindings.dart'
    if (dart.library.js_interop) 'src/generated/llama_bindings_stub.dart';
