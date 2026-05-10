import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'calls_config.dart';

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

    debugPrint('[HamsaSDK] ┌── POST participant-token ──────────────────────');
    debugPrint('[HamsaSDK] │  URL    : $url');
    debugPrint('[HamsaSDK] │  Headers: ${_safeHeaders}');
    debugPrint('[HamsaSDK] │  Body   : $body');
    debugPrint('[HamsaSDK] └────────────────────────────────────────────────');

    _addPendingLog(method: 'POST', url: url, body: body);

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: _headers,
        body: body,
      );
      final duration = DateTime.now().difference(startTime);

      debugPrint('[HamsaSDK] ┌── participant-token response (${duration.inMilliseconds}ms) ─');
      debugPrint('[HamsaSDK] │  Status: ${response.statusCode}');
      debugPrint('[HamsaSDK] │  Body  : ${response.body}');
      debugPrint('[HamsaSDK] └────────────────────────────────────────────────');

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
          debugPrint('[HamsaSDK] ✅ participant-token OK '
              '(jobId: ${data['jobId']}, '
              'token: ${token.length > 20 ? '${token.substring(0, 20)}...' : token})');
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
        debugPrint('[HamsaSDK] ❌ participant-token FAILED: $errorMsg');
        throw Exception(errorMsg);
      }
    } catch (e) {
      final duration = DateTime.now().difference(startTime);
      _updateLastLog(error: e.toString(), duration: duration);
      debugPrint('[HamsaSDK] ❌ participant-token ERROR: $e');
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

    // Log body without the enormous tools/prompt strings to keep output readable.
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
      if (channelType != null) 'channelType': channelType,
    });

    final logBody = jsonEncode({
      'tools': '[${tools?.length ?? 0} tools]',
      'voiceEnablement': true,
      'voiceAgentId': agentId,
      'params': safeParams ?? {},
      'jobId': jobId,
      if (channelType != null) 'channelType': channelType,
    });

    final startTime = DateTime.now();

    debugPrint('[HamsaSDK] ┌── POST conversation-init ──────────────────────');
    debugPrint('[HamsaSDK] │  URL    : $url');
    debugPrint('[HamsaSDK] │  Headers: ${_safeHeaders}');
    debugPrint('[HamsaSDK] │  Body   : $logBody');
    debugPrint('[HamsaSDK] └────────────────────────────────────────────────');

    _addPendingLog(method: 'POST', url: url, body: logBody);

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: _headers,
        body: body,
      );
      final duration = DateTime.now().difference(startTime);

      debugPrint('[HamsaSDK] ┌── conversation-init response (${duration.inMilliseconds}ms) ─');
      debugPrint('[HamsaSDK] │  Status: ${response.statusCode}');
      debugPrint('[HamsaSDK] │  Body  : ${response.body}');
      debugPrint('[HamsaSDK] └────────────────────────────────────────────────');

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
        debugPrint('[HamsaSDK] ❌ conversation-init FAILED: $errorMsg');
        throw Exception(errorMsg);
      }

      debugPrint('[HamsaSDK] ✅ conversation-init OK (${response.statusCode})');
    } catch (e) {
      final duration = DateTime.now().difference(startTime);
      _updateLastLog(error: e.toString(), duration: duration);
      debugPrint('[HamsaSDK] ❌ conversation-init ERROR: $e');
      rethrow;
    }
  }

  // ── Internal log helpers ─────────────────────────────────────────────────────

  void _addPendingLog({
    required String method,
    required String url,
    String? body,
  }) {
    logs.add(HamsaApiLog(
      timestamp: DateTime.now(),
      method: method,
      url: url,
      requestHeaders: _safeHeaders,
      requestBody: body,
    ));
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
