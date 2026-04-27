import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class HamsaApiService {
  final String apiKey;
  final List<HamsaApiLog> logs = [];
  
  static const String _baseUrl = 'https://api.tryhamsa.com/v1/voice-agents/room';

  HamsaApiService({required this.apiKey});

  Map<String, String> get _headers => {
        'Authorization': 'Token $apiKey',
        'Content-Type': 'application/json',
      };

  Map<String, String> get _safeHeaders => {
        'Authorization': 'Token ${_maskApiKey(apiKey)}',
        'Content-Type': 'application/json',
      };

  String _maskApiKey(String key) {
    if (key.length <= 8) return '****';
    return '${key.substring(0, 4)}****${key.substring(key.length - 4)}';
  }

  Future<Map<String, dynamic>> fetchParticipantToken(String agentId) async {
    final url = '$_baseUrl/participant-token';
    final body = jsonEncode({'voiceAgentId': agentId, 'params': {}});
    final startTime = DateTime.now();

    _addPendingLog(method: 'POST', url: url, body: body);

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: _headers,
        body: body,
      );
      final duration = DateTime.now().difference(startTime);

      _updateLastLog(
        statusCode: response.statusCode,
        responseBody: response.body,
        duration: duration,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = jsonDecode(response.body);
        if (json['success'] == true && json['data'] != null) {
          return json['data'];
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
        throw Exception(errorMsg);
      }
    } catch (e) {
      final duration = DateTime.now().difference(startTime);
      _updateLastLog(error: e.toString(), duration: duration);
      rethrow;
    }
  }

  Future<void> initializeConversation(String agentId, String jobId) async {
    final url = '$_baseUrl/conversation-init';
    final body = jsonEncode({
      'tools': [],
      'voiceEnablement': true,
      'voiceAgentId': agentId,
      'params': {},
      'jobId': jobId,
      'channelType': 'Web',
    });
    final startTime = DateTime.now();

    _addPendingLog(method: 'POST', url: url, body: body);

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: _headers,
        body: body,
      );
      final duration = DateTime.now().difference(startTime);

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
        throw Exception(errorMsg);
      }
    } catch (e) {
      final duration = DateTime.now().difference(startTime);
      _updateLastLog(error: e.toString(), duration: duration);
      rethrow;
    }
  }

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
