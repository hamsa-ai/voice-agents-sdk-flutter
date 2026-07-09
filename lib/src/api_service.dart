import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'calls_config.dart';

// Simple helper — routes to dart:developer log in debug mode only.
// Unlike debugPrint, this isn't throttled and won't truncate long strings.
void _sdkLog(String message) {
  if (kDebugMode) {
    dev.log(message, name: 'HamsaSDK');
  }
}

class HamsaApiService {
  final String apiKey;
  final CallsConfig config;
  final List<HamsaApiLog> logs = [];

  String get _baseUrl => '${config.apiUrl}/v1/voice-agents/room';

  HamsaApiService({required this.apiKey, this.config = CallsConfig.dev});

  Map<String, String> get _headers => {
    'Authorization': 'Token $apiKey',
    'Content-Type': 'application/json',
    'Accept': '*/*',
    'X-Client-Platform': 'mobile',
  };

  Map<String, String> get _safeHeaders => {
    'Authorization': 'Token ${_maskApiKey(apiKey)}',
    'Content-Type': 'application/json',
    'Accept': '*/*',
    'X-Client-Platform': 'mobile',
  };

  String _maskApiKey(String key) {
    if (key.length <= 8) return '****';
    return '${key.substring(0, 4)}****${key.substring(key.length - 4)}';
  }

  // ── participant-token ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> fetchParticipantToken(
    String agentId, {
    Map<String, dynamic>? extraParams,
  }) async {
    final url = '$_baseUrl/participant-token';
    final body = jsonEncode({
      'voiceAgentId': agentId,
      'params': extraParams ?? {},
    });
    final startTime = DateTime.now();

    _sdkLog('┌── POST participant-token ──────────────────────');
    _sdkLog('│  URL    : $url');
    _sdkLog('│  Headers: $_safeHeaders');
    _sdkLog('│  Body   : $body');
    _sdkLog('└────────────────────────────────────────────────');

    _addPendingLog(method: 'POST', url: url, body: body);

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: _headers,
        body: body,
      );
      final duration = DateTime.now().difference(startTime);

      _sdkLog('┌── participant-token response (${duration.inMilliseconds}ms) ─');
      _sdkLog('│  Status: ${response.statusCode}');
      _sdkLog('│  Body  : ${response.body}');
      _sdkLog('└────────────────────────────────────────────────');

      _updateLastLog(
        statusCode: response.statusCode,
        responseBody: response.body,
        duration: duration,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = jsonDecode(response.body);
        if (json['success'] == true && json['data'] != null) {
          final data = json['data'] as Map<String, dynamic>;
          final token = data['liveKitAccessToken'] as String? ?? '';
          _sdkLog(
            'participant-token OK '
            '(jobId: ${data['jobId']}, '
            'token: ${token.length > 20 ? '${token.substring(0, 20)}...' : token})',
          );
          return data;
        }
        throw Exception('Invalid response structure: ${response.body}');
      } else {
        String errorMsg = 'HTTP ${response.statusCode}';
        try {
          final errJson = jsonDecode(response.body);
          errorMsg = errJson['message'] ?? errJson['error'] ?? errorMsg;
        } catch (_) {
          errorMsg = '${response.statusCode}: ${response.body}';
        }
        _sdkLog('participant-token FAILED: $errorMsg');
        throw Exception(errorMsg);
      }
    } catch (e) {
      final duration = DateTime.now().difference(startTime);
      _updateLastLog(error: e.toString(), duration: duration);
      _sdkLog('participant-token ERROR: $e');
      rethrow;
    }
  }

  // ── conversation-init ────────────────────────────────────────────────────────

  Future<void> initializeConversation(
    String agentId,
    String jobId, {
    List<dynamic>? tools,
    Map<String, dynamic>? extraParams,
    String? channelType,
  }) async {
    final url = '$_baseUrl/conversation-init';

    // Log body without the enormous tools/prompt strings to keep output readable
    final safeParams = extraParams == null
        ? null
        : {
            for (final e in extraParams.entries)
              e.key: (e.value is String && (e.value as String).length > 80)
                  ? '${(e.value as String).substring(0, 80)}... [truncated]'
                  : e.value,
          };

    final body = jsonEncode({
      'tools': tools ?? [],
      'voiceEnablement': true,
      'voiceAgentId': agentId,
      'params': extraParams ?? {},
      'jobId': jobId,
      // ignore: use_null_aware_elements
      if (channelType != null) 'channelType': channelType,
    });

    final logBody = jsonEncode({
      'tools': '[${tools?.length ?? 0} tools]',
      'voiceEnablement': true,
      'voiceAgentId': agentId,
      'params': safeParams ?? {},
      'jobId': jobId,
      // ignore: use_null_aware_elements
      if (channelType != null) 'channelType': channelType,
    });

    final startTime = DateTime.now();

    _sdkLog('┌── POST conversation-init ──────────────────────');
    _sdkLog('│  URL    : $url');
    _sdkLog('│  Headers: $_safeHeaders');
    _sdkLog('│  Body   : $logBody');
    _sdkLog('└────────────────────────────────────────────────');

    _addPendingLog(method: 'POST', url: url, body: logBody);

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: _headers,
        body: body,
      );
      final duration = DateTime.now().difference(startTime);

      _sdkLog('┌── conversation-init response (${duration.inMilliseconds}ms) ─');
      _sdkLog('│  Status: ${response.statusCode}');
      _sdkLog('│  Body  : ${response.body}');
      _sdkLog('└────────────────────────────────────────────────');

      _updateLastLog(
        statusCode: response.statusCode,
        responseBody: response.body,
        duration: duration,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String errorMsg = 'HTTP ${response.statusCode}';
        try {
          final errJson = jsonDecode(response.body);
          errorMsg = errJson['message'] ?? errJson['error'] ?? errorMsg;
        } catch (_) {
          errorMsg = '${response.statusCode}: ${response.body}';
        }
        _sdkLog('conversation-init FAILED: $errorMsg');
        throw Exception(errorMsg);
      }

      _sdkLog('conversation-init OK (${response.statusCode})');
    } catch (e) {
      final duration = DateTime.now().difference(startTime);
      _updateLastLog(error: e.toString(), duration: duration);
      _sdkLog('conversation-init ERROR: $e');
      rethrow;
    }
  }

  // ── Internal log helpers ─────────────────────────────────────────────────────

  void _addPendingLog({
    required String method,
    required String url,
    String? body,
  }) {
    logs.add(
      HamsaApiLog(
        timestamp: DateTime.now(),
        method: method,
        url: url,
        requestHeaders: _safeHeaders,
        requestBody: body,
      ),
    );
  }

  void _updateLastLog({
    int? statusCode,
    String? responseBody,
    String? error,
    Duration? duration,
  }) {
    if (logs.isEmpty) return;
    final last = logs.last;
    logs[logs.length - 1] = HamsaApiLog(
      timestamp: last.timestamp,
      method: last.method,
      url: last.url,
      requestHeaders: last.requestHeaders,
      requestBody: last.requestBody,
      statusCode: statusCode,
      responseBody: responseBody,
      error: error,
      duration: duration,
    );
  }
}
