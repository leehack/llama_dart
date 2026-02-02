import 'dart:ffi';
import 'dart:io';

/// Opens the llama native library.
DynamicLibrary? openLibrary() {
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
