import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'src/models.dart';
import 'src/api_service.dart';
import 'src/voice_service.dart';
import 'src/calls_config.dart';

export 'src/models.dart';
export 'src/calls_config.dart';

/// Main class for the Hamsa Voice Agent SDK.
/// Use [start] to connect to a Hamsa AI agent and manage the conversation.
class HamsaVoiceAgent {
  final String apiKey;
  final HamsaApiService _apiService;
  final HamsaVoiceService _voiceService = HamsaVoiceService();

  HamsaConnectionStatus _status = HamsaConnectionStatus.disconnected;
  HamsaAgentState _agentState = HamsaAgentState.idle;
  EventsListener<RoomEvent>? _listener;
  bool _isPaused = false;
  Timer? _radarTimer;

  // ── Callbacks ───────────────────────────────────────────────────────────────

  void Function(HamsaConnectionStatus status)? onConnectionStatusChanged;
  void Function(HamsaAgentState state)? onAgentStateChanged;
  void Function(String text)? onTranscriptionReceived;
  void Function(String context)? onAgentContextReceived;
  void Function(String text)? onAnswerReceived;
  void Function(String errorMessage)? onError;

  /// Fires when the Render Engine calls a client-side UI tool during an
  /// interactive call. The app must render the appropriate UI and call
  /// [resolveToolCall] when the user submits a result.
  ///
  /// [toolCall.name] is one of: show_options, confirm_data, show_summary,
  /// enter_number, enter_text, pick_date, ask_yes_no, show_info,
  /// dismiss_tool_ui, prefill_active_tool.
  void Function(HamsaToolCall toolCall)? onToolCall;

  // ── Constructor / getters ───────────────────────────────────────────────────

  HamsaVoiceAgent({required this.apiKey, CallsConfig? config})
    : _apiService = HamsaApiService(
        apiKey: apiKey,
        config: config ?? CallsConfig.getCallsConfig(),
      ),
      _liveKitUrl = (config ?? CallsConfig.getCallsConfig()).liveKitUrl;

  final String _liveKitUrl;

  HamsaConnectionStatus get status => _status;
  HamsaAgentState get agentState => _agentState;
  List<HamsaApiLog> get apiLogs => _apiService.logs;
  bool get isPaused => _isPaused;

  // ── Call lifecycle ──────────────────────────────────────────────────────────

  /// Starts a new conversation with the specified agent.
  ///
  /// Set [interactiveAgent] to true when the agent is configured for
  /// interactive UI tools (branding.interactiveAgent === true). The SDK will
  /// then register all RPC handlers and fire [onToolCall] during the call.
  Future<void> start(
    String agentId, {
    Map<String, dynamic>? customParams,
    List<HamsaTool>? customTools,
    @Deprecated('Use customParams and customTools instead')
    bool interactiveAgent = false,
  }) async {
    debugPrint('');
    debugPrint('[HamsaSDK] ═══════════════════════════════════════════════');
    debugPrint('[HamsaSDK]  CALL START');
    debugPrint('[HamsaSDK]  agentId    : $agentId');
    debugPrint('[HamsaSDK]  apiKey     : ${_maskKey(apiKey)}');
    debugPrint('[HamsaSDK]  interactive: $interactiveAgent');
    debugPrint('[HamsaSDK] ═══════════════════════════════════════════════');

    try {
      _updateStatus(HamsaConnectionStatus.connecting);
      debugPrint('[HamsaSDK] [1/5] Fetching participant-token...');

      // participant-token: We MUST send the tools and flags here, just like
      // the web SDK does, because the backend relies on this to spawn the
      // render engine into the room.
      final tokenData = await _apiService.fetchParticipantToken(
        agentId,
        extraParams: {
          'voiceEnablement': 'true',
          if (customParams != null) ...customParams,
        },
      );
      final token = tokenData['liveKitAccessToken'] as String;

      final jobId =
          _extractJobIdFromToken(token) ??
          tokenData['jobId'] as String? ??
          agentId;

      // Wire the RPC bridge BEFORE connecting so _registerRpcHandlers()
      // sees a non-null onToolCall when connect() is called.
      debugPrint('[HamsaSDK] [3/5] Wiring RPC bridge...');
      if (onToolCall != null) {
        _voiceService.onToolCall = (name, args, callId) {
          debugPrint(
            '[HamsaSDK] 🔔 Tool call received: $name (callId: $callId)',
          );
          onToolCall!.call(
            HamsaToolCall(name: name, args: args, callId: callId),
          );
        };
      }

      debugPrint('[HamsaSDK] [4/5] Connecting to LiveKit room...');
      final room = await _voiceService.connect(token, url: _liveKitUrl);
      _setUpListeners(room);

      // ── Room Radar: Log all members every 5s ──────────────────────────────
      _radarTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (room.connectionState != ConnectionState.connected) {
          timer.cancel();
          return;
        }
        final participants = room.remoteParticipants.values;
        final info = participants
            .map((p) {
              return '${p.identity} (Quality: ${p.connectionQuality}, Meta: ${p.metadata})';
            })
            .join('\n      ');

        debugPrint(
          '[HamsaSDK] 🛰  Room Radar (${participants.length} remotes):\n      $info',
        );
      });

      // ── conversation-init ──────────────────────────────────────────────────

      debugPrint(
        '[HamsaSDK] [5/5] Initializing conversation (jobId: $jobId)...',
      );
      await _apiService.initializeConversation(
        agentId,
        jobId,
        tools: customTools?.map((t) => t.toLLMJson()).toList(),
        extraParams: customParams,
        channelType: 'Web',
      );

      debugPrint('[HamsaSDK] Initialization complete.');
      _updateStatus(HamsaConnectionStatus.connected);
      _isPaused = false;

      debugPrint('[HamsaSDK] CALL CONNECTED — waiting for agent to speak.');
      debugPrint('[HamsaSDK] ═══════════════════════════════════════════════');
    } catch (e) {
      debugPrint('[HamsaSDK] CALL START FAILED: $e');
      debugPrint('[HamsaSDK] ═══════════════════════════════════════════════');
      _updateStatus(HamsaConnectionStatus.error);
      onError?.call(e.toString());
      await stop();
      rethrow;
    }
  }

  /// Submits a result for a tool call (e.g. from an interactive UI component).
  /// [callId] is the id of the tool call being responded to.
  /// [result] is a JSON-serializable map.
  Future<void> submitToolResult(
    String callId,
    Map<String, dynamic> result,
  ) async {
    _voiceService.resolveToolCall(callId, result);
    debugPrint('[HamsaSDK] 📤 Tool result resolved: $callId');
  }

  /// Stops the current conversation and releases resources.
  Future<void> stop() async {
    debugPrint('[HamsaSDK] ───────────────────────────────────────────────');
    debugPrint('[HamsaSDK]  CALL STOP — disconnecting...');
    await _voiceService.disconnect();
    _radarTimer?.cancel();
    _listener?.dispose();
    _listener = null;
    _updateStatus(HamsaConnectionStatus.disconnected);
    _updateAgentState(HamsaAgentState.idle);
    _isPaused = false;
    debugPrint('[HamsaSDK]  Disconnected. Resources released.');
    debugPrint('[HamsaSDK] ───────────────────────────────────────────────');
  }

  // ── Tool result resolution ──────────────────────────────────────────────────

  /// Called by the app after the user interacts with a tool overlay.
  /// [callId] must match the [HamsaToolCall.callId] that was delivered via [onToolCall].
  /// [result] is the JSON-serialisable result object (e.g. {'selected_id': 'opt_1', ...}).
  void resolveToolCall(String callId, Map<String, dynamic> result) {
    debugPrint('[HamsaSDK] resolveToolCall: callId=$callId result=$result');
    _voiceService.resolveToolCall(callId, result);
  }

  /// Sends text input from the user back to the voice agent (Voice Mirror)
  Future<void> sendInput(String text) async {
    await _voiceService.sendInput(text);
  }

  // ── Audio controls ──────────────────────────────────────────────────────────

  Future<void> pause() async {
    debugPrint('[HamsaSDK] ⏸  pause()');
    await _voiceService.pause();
    _isPaused = true;
  }

  Future<void> resume() async {
    debugPrint('[HamsaSDK] ▶️  resume()');
    await _voiceService.resume();
    _isPaused = false;
  }

  Future<void> setMuted(bool muted) async {
    debugPrint('[HamsaSDK] 🎙  setMuted($muted)');
    await _voiceService.setMicrophoneMuted(muted);
  }

  Future<void> setSpeakerphoneOn(bool enabled) async {
    debugPrint('[HamsaSDK] 🔊  setSpeakerphoneOn($enabled)');
    await _voiceService.setSpeakerphoneOn(enabled);
  }

  bool get isSpeakerphoneOn => _voiceService.isSpeakerphoneOn;

  void setVolume(double volume) {
    _voiceService.setVolume(volume);
  }

  void sendDTMF(String digit) {
    _voiceService.sendDTMF(digit);
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  void _updateStatus(HamsaConnectionStatus newStatus) {
    debugPrint('[HamsaSDK] 🔄 Status: $_status → $newStatus');
    _status = newStatus;
    onConnectionStatusChanged?.call(newStatus);
  }

  void _updateAgentState(HamsaAgentState newState) {
    if (_agentState != newState) {
      debugPrint('[HamsaSDK] 🔄 AgentState: $_agentState → $newState');
    }
    _agentState = newState;
    onAgentStateChanged?.call(newState);
  }

  void _setUpListeners(Room room) {
    _listener = room.createListener();

    // ── Room disconnected ──────────────────────────────────────────────────
    _listener!.on<RoomDisconnectedEvent>((event) {
      debugPrint(
        '[HamsaSDK] 🔌 Room disconnected '
        '(reason: ${event.reason})',
      );
      _updateStatus(HamsaConnectionStatus.disconnected);
    });

    // ── Active speakers ────────────────────────────────────────────────────
    _listener!.on<ActiveSpeakersChangedEvent>((event) {
      if (_isPaused) return;
      final remoteSpeakers = event.speakers
          .where((p) => p != room.localParticipant)
          .toList();
      final isAgentSpeaking = remoteSpeakers.isNotEmpty;
      if (isAgentSpeaking) {
        debugPrint(
          '[HamsaSDK] 🗣  Agent speaking: '
          '${remoteSpeakers.map((p) => p.identity).join(', ')}',
        );
      }
      _updateAgentState(
        isAgentSpeaking ? HamsaAgentState.speaking : HamsaAgentState.listening,
      );
    });

    // ── Track subscribed — CRITICAL: must call .enable() for audio ─────────
    _listener!.on<TrackPublishedEvent>((event) {
      debugPrint(
        '[HamsaSDK] 📤 Track published by ${event.participant.identity}: '
        '${event.publication.sid} (${event.publication.kind})',
      );
    });

    _listener!.on<TrackSubscribedEvent>((event) {
      debugPrint(
        '[HamsaSDK] 📡 Track subscribed: ${event.track.sid} '
        'from ${event.participant.identity} (${event.track.kind})',
      );

      if (event.track is RemoteAudioTrack) {
        final audioTrack = event.track as RemoteAudioTrack;
        audioTrack.enable();
        try {
          (audioTrack as dynamic).start();
        } catch (_) {}
        debugPrint('[HamsaSDK] 🔊 Remote audio track ENABLED & STARTED');
      }
    });

    // ── Local Diagnostics ──────────────────────────────────────────────────
    final local = room.localParticipant;
    if (local != null) {
      debugPrint('[HamsaSDK] 🎙  Local participant: ${local.identity}');
      debugPrint(
        '[HamsaSDK] 🎙  Local tracks published: ${local.audioTrackPublications.length} audio',
      );
    }

    // ── Track unsubscribed ─────────────────────────────────────────────────
    _listener!.on<TrackUnsubscribedEvent>((event) {
      debugPrint(
        '[HamsaSDK] 📡 Track unsubscribed: '
        'kind=${event.track.kind} '
        'from=${event.participant.identity}',
      );
    });

    // ── Remote participant joined ───────────────────────────────────────────
    _listener!.on<ParticipantConnectedEvent>((event) {
      debugPrint(
        '[HamsaSDK] 👤 Remote participant joined: '
        '${event.participant.identity} '
        '(sid: ${event.participant.sid})',
      );
    });

    // ── Remote participant left ────────────────────────────────────────────
    _listener!.on<ParticipantDisconnectedEvent>((event) {
      debugPrint(
        '[HamsaSDK] 👤 Remote participant left: '
        '${event.participant.identity}',
      );
    });

    // ── Data messages (transcription etc.) ────────────────────────────────
    _listener!.on<DataReceivedEvent>((event) {
      try {
        final text = utf8.decode(event.data);
        debugPrint(
          '[HamsaSDK] 📨 Data received from '
          '${event.participant?.identity}: $text',
        );

        final json = jsonDecode(text);
        if (json is Map<String, dynamic>) {
          if (json['type'] == 'render_ctx' && json['content'] != null) {
            onAgentContextReceived?.call(json['content'] as String);
          }
        }
      } catch (_) {}
    });

    // Race-condition safety: enable any tracks already in the room.
    debugPrint('[HamsaSDK] Scanning existing remote tracks...');
    for (final participant in room.remoteParticipants.values) {
      debugPrint(
        '[HamsaSDK]   Participant: ${participant.identity} '
        '(audio tracks: ${participant.audioTrackPublications.length})',
      );
      for (final pub in participant.audioTrackPublications) {
        final track = pub.track;
        if (track is RemoteAudioTrack) {
          track.enable();
          debugPrint(
            '[HamsaSDK]   ↳ Enabled existing audio track: ${track.sid}',
          );
        } else {
          debugPrint(
            '[HamsaSDK]   ↳ Audio pub found but track not yet '
            'subscribed (sid: ${pub.sid})',
          );
        }
      }
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _maskKey(String key) {
    if (key.length <= 8) return '****';
    return '${key.substring(0, 4)}****${key.substring(key.length - 4)}';
  }

  String? _extractJobIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final map = jsonDecode(decoded);

      debugPrint('[HamsaSDK] JWT payload keys: ${map.keys.toList()}');

      // Extract room ID from video.room
      final roomId = map['video']?['room'] as String?;
      if (roomId != null) {
        debugPrint('[HamsaSDK] 🏠 LiveKit Room ID: $roomId');
      }

      final agents = map['roomConfig']?['agents'] as List?;
      if (agents != null && agents.isNotEmpty) {
        final metadataStr = agents[0]['metadata'] as String?;
        if (metadataStr != null) {
          final metadata = jsonDecode(metadataStr);
          final jobId = metadata['jobId'] as String?;
          debugPrint('[HamsaSDK] JWT jobId extracted: $jobId');
          return jobId;
        }
      }
      debugPrint('[HamsaSDK] JWT: no jobId in roomConfig.agents');
    } catch (e) {
      debugPrint('[HamsaSDK] JWT decode error: $e');
    }
    return null;
  }
}
