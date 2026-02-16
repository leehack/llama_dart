/// Exposes token-count capability.
abstract class EngineTokenCountPort {
  /// Computes token count for a text payload.
  Future<int> getTokenCount(String text);
}
