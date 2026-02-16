import '../../../../server_engine/server_engine.dart';

/// Coordinates single-flight generation and cancellation.
class GenerationGate {
  final EngineCancellationPort _engine;

  bool _isGenerating = false;

  /// Creates a gate bound to one [EngineCancellationPort].
  GenerationGate(this._engine);

  /// Whether a generation is currently active.
  bool get isGenerating => _isGenerating;

  /// Attempts to acquire the generation slot.
  bool tryAcquire() {
    if (_isGenerating) {
      return false;
    }

    _isGenerating = true;
    return true;
  }

  /// Releases the generation slot and cancels generation on the engine.
  void release() {
    _engine.cancelGeneration();
    _isGenerating = false;
  }
}
