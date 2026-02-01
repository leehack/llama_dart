import 'dart:ffi';
import 'dart:io';
export '../generated/llama_bindings.dart';

const bool _kIsWeb = identical(0, 0.0);

/// The underlying DynamicLibrary, exposed for NativeFinalizer access.
///
/// This uses the Native Assets mapping for 'package:llamadart/llamadart'.
/// If it fails (e.g. in some isolate contexts), it returns null.
final DynamicLibrary? llamaLib = _kIsWeb ? null : _openLibrary();

DynamicLibrary? _openLibrary() {
  if (_kIsWeb) return null;
  try {
    final lib = DynamicLibrary.open('package:llamadart/llamadart');
    return lib;
  } catch (e) {
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        // For Apple platforms, if Native Assets failed, it might be
        // because the library was statically linked into the executable.
        final lib = DynamicLibrary.executable();
        return lib;
      }

      final libName = Platform.isWindows
          ? 'libllamadart.dll'
          : 'libllamadart.so'; // Linux/Android
      final lib = DynamicLibrary.open(libName);
      return lib;
    } catch (_) {
      return null;
    }
  }
}
