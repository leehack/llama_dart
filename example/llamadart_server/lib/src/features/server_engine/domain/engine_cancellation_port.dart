/// Exposes generation cancellation capability.
abstract class EngineCancellationPort {
  /// Cancels active generation.
  void cancelGeneration();
}
