import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

class HamsaVoiceService {
  Room? _room;
  Room? get room => _room;

  static const String _defaultUrl = 'wss://rtc.eu.tryhamsa.com';

  // ── Interactive / RPC state ─────────────────────────────────────────────────

  /// Fires when the Render Engine calls a tool — blocking tools hold until resolved.
  /// Signature: (toolName, args, callId)
  void Function(String, Map<String, dynamic>, String)? onToolCall;

  Completer<String>? _activeCompleter;
  String? _activeCallId;

  static const List<String> _blockingTools = [
    'show_options',
    'confirm_data',
    'show_summary',
    'enter_number',
    'enter_text',
    'pick_date',
    'ask_yes_no',
    'show_paths',
  ];

  // ── Connect / disconnect ────────────────────────────────────────────────────

  Future<Room> connect(String token, {String? url}) async {
    await _room?.disconnect();

    final roomOptions = RoomOptions(
      adaptiveStream: true,
      dynacast: true,
      defaultAudioPublishOptions: const AudioPublishOptions(dtx: true),
    );

    final room = Room(roomOptions: roomOptions);
    await room.connect(url ?? _defaultUrl, token);

    // publish microphone
    await room.localParticipant?.setMicrophoneEnabled(true);

    _room = room;

    // Register RPC handlers on the Room (RoomRPCMethods extension) only when
    // interactive mode is enabled.
    if (onToolCall != null) {
      _registerRpcHandlers(room);
    }

    return room;
  }

  Future<void> disconnect() async {
    _dismissActive(); // resolve any pending tool call before teardown
    // Unregister all RPC handlers before disconnecting
    if (_room != null) {
      for (final toolName in _blockingTools) {
        _room!.unregisterRpcMethod(toolName);
      }
      _room!.unregisterRpcMethod('show_info');
      _room!.unregisterRpcMethod('dismiss_tool_ui');
      _room!.unregisterRpcMethod('prefill_active_tool');
    }
    await _room?.disconnect();
    await _room?.dispose();
    _room = null;
  }

  // ── RPC registration ────────────────────────────────────────────────────────

  void _registerRpcHandlers(Room room) {
    // ── Blocking tools ──────────────────────────────────────────────────────
    for (final toolName in _blockingTools) {
      room.registerRpcMethod(toolName, (data) async {
        // Preempt any previous pending call
        _dismissActive();

        final callId = data.requestId;
        final completer = Completer<String>();
        _activeCompleter = completer;
        _activeCallId = callId;

        final Map<String, dynamic> args = _safeDecodeArgs(data.payload);
        debugPrint('[HamsaSDK] ⚡ RECEIVED RPC TOOL CALL: $toolName (callId: $callId)');
        debugPrint('[HamsaSDK] ⚡ PAYLOAD: $args');
        
        onToolCall?.call(toolName, args, callId);

        // Block LiveKit RPC until app resolves, with 120 s safety timeout
        return completer.future.timeout(
          const Duration(seconds: 120),
          onTimeout: () {
            _activeCompleter = null;
            _activeCallId = null;
            return jsonEncode({'timed_out': true});
          },
        );
      });
    }

    // ── show_info — non-blocking ────────────────────────────────────────────
    room.registerRpcMethod('show_info', (data) async {
      final Map<String, dynamic> args = _safeDecodeArgs(data.payload);
      onToolCall?.call('show_info', args, data.requestId);
      return jsonEncode({'shown': true}); // resolves immediately
    });

    // ── dismiss_tool_ui ────────────────────────────────────────────────────
    room.registerRpcMethod('dismiss_tool_ui', (data) async {
      _dismissActive(); // complete pending with dismissed
      onToolCall?.call('dismiss_tool_ui', {}, data.requestId);
      return jsonEncode({'dismissed': true});
    });

    // ── prefill_active_tool — non-blocking helper ──────────────────────────
    room.registerRpcMethod('prefill_active_tool', (data) async {
      final Map<String, dynamic> args = _safeDecodeArgs(data.payload);
      onToolCall?.call('prefill_active_tool', args, data.requestId);
      return jsonEncode({'updated': true});
    });

    debugPrint('[HamsaSDK] Registered ${_blockingTools.length + 3} RPC handlers on Room');
  }

  // ── Tool result resolution ──────────────────────────────────────────────────

  /// Called by the app after the user submits a tool response.
  void resolveToolCall(String callId, Map<String, dynamic> result) {
    if (_activeCallId == callId &&
        _activeCompleter != null &&
        !_activeCompleter!.isCompleted) {
      _activeCompleter!.complete(jsonEncode(result));
      _activeCompleter = null;
      _activeCallId = null;
    } else {
      debugPrint('[HamsaSDK] resolveToolCall: no pending call for id=$callId');
    }
  }

  /// Dismiss the active blocking tool call with {dismissed: true}.
  void _dismissActive() {
    if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
      _activeCompleter!.complete(jsonEncode({'dismissed': true}));
    }
    _activeCompleter = null;
    _activeCallId = null;
  }

  // ── Audio controls ──────────────────────────────────────────────────────────

  Future<void> setMicrophoneMuted(bool muted) async {
    await _room?.localParticipant?.setMicrophoneEnabled(!muted);
  }

  Future<void> setSpeakerphoneOn(bool enabled) async {
    await Hardware.instance.setSpeakerphoneOn(enabled);
  }

  bool get isSpeakerphoneOn => Hardware.instance.speakerOn ?? false;

  void setVolume(double volume) {
    if (_room == null) return;
    for (var participant in _room!.remoteParticipants.values) {
      for (var track in participant.audioTrackPublications) {
        final t = track.track;
        if (t is RemoteAudioTrack) {
          try {
            (t as dynamic).setVolume(volume);
          } catch (_) {}
        }
      }
    }
  }

  Future<void> pause() async {
    if (_room == null) return;
    await setMicrophoneMuted(true);
    for (var participant in _room!.remoteParticipants.values) {
      for (var track in participant.audioTrackPublications) {
        if (track.kind == TrackType.AUDIO) {
          try {
            (track as dynamic).unsubscribe();
          } catch (_) {}
        }
      }
    }
  }

  Future<void> resume() async {
    if (_room == null) return;
    await setMicrophoneMuted(false);
    for (var participant in _room!.remoteParticipants.values) {
      for (var track in participant.audioTrackPublications) {
        if (track.kind == TrackType.AUDIO) {
          try {
            (track as dynamic).subscribe();
          } catch (_) {}
        }
      }
    }
  }

  void sendDTMF(String digit) {
    final localParticipant = _room?.localParticipant;
    if (localParticipant == null) return;
    final code = _dtmfMap[digit];
    if (code != null) {
      debugPrint(
          '[HamsaSDK] DTMF $digit (code: $code) requested but not yet implemented in this version.');
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _safeDecodeArgs(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return {};
  }

  static const Map<String, int> _dtmfMap = {
    '0': 0, '1': 1, '2': 2, '3': 3, '4': 4,
    '5': 5, '6': 6, '7': 7, '8': 8, '9': 9,
    '*': 10, '#': 11,
  };
}
