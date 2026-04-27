/// connection states for the Hamsa voice agent
enum HamsaConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// agent interaction states
enum HamsaAgentState {
  idle,
  initializing,
  listening,
  thinking,
  speaking,
}

/// event data for call started
class HamsaCallStartedData {
  final String jobId;
  HamsaCallStartedData({required this.jobId});
}

/// API log entry for troubleshooting
class HamsaApiLog {
  final DateTime timestamp;
  final String method;
  final String url;
  final Map<String, String> requestHeaders;
  final String? requestBody;
  final int? statusCode;
  final String? responseBody;
  final String? error;
  final Duration? duration;

  HamsaApiLog({
    required this.timestamp,
    required this.method,
    required this.url,
    required this.requestHeaders,
    this.requestBody,
    this.statusCode,
    this.responseBody,
    this.error,
    this.duration,
  });

  bool get isSuccess => statusCode != null && statusCode! >= 200 && statusCode! < 300;
  bool get isError => error != null || (statusCode != null && statusCode! >= 400);
}
