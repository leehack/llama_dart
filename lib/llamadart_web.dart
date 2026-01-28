import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// The web implementation of the LlamaDart plugin.
class LlamaDartWeb {
  /// Registers this class as the default instance of the plugin.
  static void registerWith(Registrar registrar) {
    // No-op: The plugin is implemented using Dart conditional imports
    // and direct JS interop, not MethodChannels.
    // This class primarily exists to satisfy pubspec.yaml configuration.
  }
}
