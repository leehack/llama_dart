/// Exposes readiness state for an inference engine.
abstract class EngineReadinessPort {
  /// Whether the engine is loaded and ready.
  bool get isReady;
}
