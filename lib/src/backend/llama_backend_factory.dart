import 'llama_backend_interface.dart';

/// Creates the appropriate backend for the current platform.
/// This is a fallback stub used when platform-specific implementations are not available.
LlamaBackend createBackend() => throw UnsupportedError(
  'LlamaBackend is not supported on this platform. '
  'Ensure you have the correct library (ffi or js_interop) available.',
);
