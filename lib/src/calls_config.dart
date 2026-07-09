/// Voice Calls Environment Configuration
///
/// Mirrors the web SDK's environment config pattern.
/// Environment is detected via --dart-define=ENV=production|staging|dev
/// or falls back to kDebugMode (dev) / release (production).

import 'package:flutter/foundation.dart';

/// Supported region identifiers.
enum CallsRegion { eu, uae }

/// Configuration for the Hamsa voice SDK.
class CallsConfig {
  /// Hamsa REST API base URL (without trailing slash).
  final String apiUrl;

  /// LiveKit WebSocket URL.
  final String liveKitUrl;

  /// Enable verbose SDK debug logging.
  final bool debug;

  const CallsConfig({
    required this.apiUrl,
    required this.liveKitUrl,
    this.debug = false,
  });

  // ── Presets ──────────────────────────────────────────────────────────────

  /// EU Production
  static const production = CallsConfig(
    apiUrl: 'https://api.tryhamsa.com',
    liveKitUrl: 'wss://rtc.eu.tryhamsa.com',
  );

  /// UAE Production
  static const productionUae = CallsConfig(
    apiUrl: 'https://api.tryhamsa.com',
    liveKitUrl: 'wss://rtc.uae.tryhamsa.com',
  );

  /// Staging
  static const staging = CallsConfig(
    apiUrl: 'https://api-green.tryhamsa.com',
    liveKitUrl: 'wss://rtc.tryhamsa.com',
  );

  /// Development
  static const dev = CallsConfig(
    apiUrl: 'https://api-dev.tryhamsa.com',
    liveKitUrl: 'wss://rtc.tryhamsa.com',
    debug: true,
  );

  // ── Auto-detection (mirrors web hostname detection) ───────────────────────

  /// Automatically picks the right config based on:
  /// 1. --dart-define=ENV=production|production_uae|staging|dev
  /// 2. --dart-define=CALLS_REGION=uae  (forces UAE endpoints)
  /// 3. Falls back to debug mode → dev, release mode → production
  ///
  /// Usage in flutter run / flutter build:
  ///   flutter run --dart-define=ENV=staging
  ///   flutter build apk --dart-define=ENV=production
  static CallsConfig getCallsConfig() {
    const env = String.fromEnvironment('ENV');
    const region = String.fromEnvironment('CALLS_REGION');

    // Region override — always UAE endpoints regardless of env
    if (region == 'uae') return productionUae;

    switch (env) {
      case 'production':
        return production;
      case 'production_uae':
        return productionUae;
      case 'staging':
        return staging;
      case 'dev':
        return dev;
      default:
        // No dart-define: infer from Flutter build mode
        if (kDebugMode) return dev;
        if (kProfileMode) return staging;
        return production; // kReleaseMode
    }
  }

  @override
  String toString() =>
      'CallsConfig(api: $apiUrl, liveKit: $liveKitUrl, debug: $debug)';
}
