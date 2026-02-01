/// High-performance Dart and Flutter plugin for llama.cpp.
library;

// Models
export 'src/models/model_params.dart';
export 'src/models/generation_params.dart';
export 'src/models/llama_chat_message.dart';
export 'src/models/llama_chat_template_result.dart';
export 'src/models/llama_log_level.dart';
export 'src/models/gpu_backend.dart';
export 'src/models/lora_adapter_config.dart';

// Engine
export 'src/engine/llama_engine.dart';
export 'src/engine/llama_tokenizer.dart';
export 'src/engine/chat_template_processor.dart';

// Backends - hide createBackend to avoid conflict with factory export
export 'src/backend/llama_backend_interface.dart';
export 'src/backend/native/native_backend.dart'
    if (dart.library.js_interop) 'src/backend/web/web_backend.dart'
    hide createBackend;

// Factory
export 'src/backend/llama_backend_factory.dart'
    if (dart.library.ffi) 'src/backend/native/native_backend.dart'
    if (dart.library.js_interop) 'src/backend/web/web_backend.dart';

// Common
export 'src/common/exceptions.dart';
export 'src/generated/llama_bindings.dart'
    if (dart.library.js_interop) 'src/generated/llama_bindings_stub.dart';
