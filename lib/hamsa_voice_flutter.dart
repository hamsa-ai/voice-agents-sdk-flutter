import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'src/models.dart';
import 'src/api_service.dart';
import 'src/voice_service.dart';

export 'src/models.dart';

/// main class for the Hamsa Voice Agent SDK.
/// use this class to connect to Hamsa AI agents and manage the conversation.
class HamsaVoiceAgent {
  final String apiKey;
  final HamsaApiService _apiService;
  final HamsaVoiceService _voiceService = HamsaVoiceService();
  
  HamsaConnectionStatus _status = HamsaConnectionStatus.disconnected;
  HamsaAgentState _agentState = HamsaAgentState.idle;
  EventsListener<RoomEvent>? _listener;
  bool _isPaused = false;
  
  // callbacks
  void Function(HamsaConnectionStatus status)? onConnectionStatusChanged;
  void Function(HamsaAgentState state)? onAgentStateChanged;
  void Function(String text)? onTranscriptionReceived;
  void Function(String text)? onAnswerReceived;
  void Function(String errorMessage)? onError;

  HamsaVoiceAgent({required this.apiKey}) : _apiService = HamsaApiService(apiKey: apiKey);

  HamsaConnectionStatus get status => _status;
  HamsaAgentState get agentState => _agentState;
  List<HamsaApiLog> get apiLogs => _apiService.logs;
  bool get isPaused => _isPaused;

  /// starts a new conversation with the specified agent.
  Future<void> start(String agentId) async {
    try {
      _updateStatus(HamsaConnectionStatus.connecting);

      debugPrint('[HamsaSDK] Fetching token for agent: $agentId');
      final tokenData = await _apiService.fetchParticipantToken(agentId);
      final token = tokenData['liveKitAccessToken'] as String;
      
      // extract jobId from token metadata (just like JS SDK.)
      final jobId = _extractJobIdFromToken(token) ?? tokenData['jobId'] as String? ?? agentId;

      debugPrint('[HamsaSDK] Connecting to LiveKit...');
      final room = await _voiceService.connect(token);
      _setUpListeners(room);

      debugPrint('[HamsaSDK] Initializing conversation (jobId: $jobId)...');
      await _apiService.initializeConversation(agentId, jobId);

      _updateStatus(HamsaConnectionStatus.connected);
      _isPaused = false;
    } catch (e) {
      debugPrint('[HamsaSDK] Connection failed: $e');
      _updateStatus(HamsaConnectionStatus.error);
      onError?.call(e.toString());
      await stop();
      rethrow;
    }
  }

  /// stops the current conversation and releases resources.
  Future<void> stop() async {
    await _voiceService.disconnect();
    _listener?.dispose();
    _listener = null;
    _updateStatus(HamsaConnectionStatus.disconnected);
    _updateAgentState(HamsaAgentState.idle);
    _isPaused = false;
  }

  /// temporarily pauses the conversation (mutes both user and agent).
  Future<void> pause() async {
    await _voiceService.pause();
    _isPaused = true;
  }

  /// resumes a paused conversation.
  Future<void> resume() async {
    await _voiceService.resume();
    _isPaused = false;
  }

  /// toggles the microphone mute state.
  Future<void> setMuted(bool muted) async {
    await _voiceService.setMicrophoneMuted(muted);
  }

  /// toggles the device speakerphone.
  Future<void> setSpeakerphoneOn(bool enabled) async {
    await _voiceService.setSpeakerphoneOn(enabled);
  }

  /// gets the current speakerphone status.
  bool get isSpeakerphoneOn => _voiceService.isSpeakerphoneOn;

  /// sets the volume for the conversation (0.0 to 1.0).
  void setVolume(double volume) {
    _voiceService.setVolume(volume);
  }

  /// sends a DTMF digit (0-9, *, #) during an active call.
  /// useful for interacting with IVR systems or dial pad testing.
  void sendDTMF(String digit) {
    _voiceService.sendDTMF(digit);
  }

  void _updateStatus(HamsaConnectionStatus newStatus) {
    _status = newStatus;
    onConnectionStatusChanged?.call(newStatus);
  }

  void _updateAgentState(HamsaAgentState newState) {
    _agentState = newState;
    onAgentStateChanged?.call(newState);
  }

  void _setUpListeners(Room room) {
    _listener = room.createListener();
    _listener!.on<RoomDisconnectedEvent>((event) {
      _updateStatus(HamsaConnectionStatus.disconnected);
    });

    _listener!.on<ActiveSpeakersChangedEvent>((event) {
      if (_isPaused) return; // ignore speaker updates if paused
      final isAgentSpeaking = event.speakers.where((p) => p != room.localParticipant).isNotEmpty;
      _updateAgentState(isAgentSpeaking ? HamsaAgentState.speaking : HamsaAgentState.listening);
    });
  }

  String? _extractJobIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = parts[1];
      var normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final map = jsonDecode(decoded);
      
      final agents = map['roomConfig']?['agents'] as List?;
      if (agents != null && agents.isNotEmpty) {
        final metadataStr = agents[0]['metadata'] as String?;
        if (metadataStr != null) {
          final metadata = jsonDecode(metadataStr);
          return metadata['jobId'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }
}
