import 'llama_backend_interface.dart';
import 'native/native_backend.dart';

/// Creates the appropriate backend for the current platform.
LlamaBackend createBackend() => NativeLlamaBackend();
