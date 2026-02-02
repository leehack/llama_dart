import 'loader_native.dart' if (dart.library.js_interop) 'loader_web.dart';

export '../generated/llama_bindings.dart'
    if (dart.library.js_interop) '../generated/llama_bindings_stub.dart';

/// The underlying DynamicLibrary (on native platforms) or null (on web).
///
/// This uses the Native Assets mapping for 'package:llamadart/llamadart'.
/// If it fails (e.g. in some isolate contexts), it returns null.
final dynamic llamaLib = openLibrary();
