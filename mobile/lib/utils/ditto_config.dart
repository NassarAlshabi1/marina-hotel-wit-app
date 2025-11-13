class DittoConfig {
  static const bool enableCloudTransport = true;
  static const bool autoStartSync = false;

  static String deviceName(String fallback) => 'Marina Hotel (${fallback.isEmpty ? 'device' : fallback})';
}
