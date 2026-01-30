import 'dart:ffi';
import 'dart:io';
export 'generated/llama_bindings.dart';

/// The underlying DynamicLibrary, exposed for NativeFinalizer access.
///
/// This uses the Native Assets mapping for 'package:llamadart/llama_cpp'.
/// If it fails (e.g. in some isolate contexts), it returns null.
final DynamicLibrary? llamaLib = _openLibrary();

DynamicLibrary? _openLibrary() {
  try {
    return DynamicLibrary.open('package:llamadart/llamadart');
  } catch (_) {
    try {
      // Fallback to name-only open which works if the library was bundled
      // or is in the standard library search path.
      final libName = Platform.isWindows
          ? 'libllamadart.dll'
          : Platform.isMacOS
          ? 'libllamadart.dylib'
          : 'libllamadart.so';
      return DynamicLibrary.open(libName);
    } catch (_) {
      return null;
    }
  }
}
