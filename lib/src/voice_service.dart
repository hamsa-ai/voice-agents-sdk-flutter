import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

class HamsaVoiceService {
  Room? _room;

  static const String _defaultUrl = 'wss://rtc.eu.tryhamsa.com';

  Future<Room> connect(String token, {String? url}) async {
    await _room?.disconnect();

    final roomOptions = RoomOptions(
      adaptiveStream: true,
      dynacast: true,
      defaultAudioPublishOptions: const AudioPublishOptions(
        dtx: true,
      ),
    );

    final room = Room(roomOptions: roomOptions);
    await room.connect(url ?? _defaultUrl, token);
    
    // publish microphone
    await room.localParticipant?.setMicrophoneEnabled(true);
    
    _room = room;
    return room;
  }

  Future<void> disconnect() async {
    await _room?.disconnect();
    await _room?.dispose();
    _room = null;
  }

  /// mutes or unmutes the local microphone.
  Future<void> setMicrophoneMuted(bool muted) async {
    await _room?.localParticipant?.setMicrophoneEnabled(!muted);
  }

  /// toggles the device speakerphone.
  Future<void> setSpeakerphoneOn(bool enabled) async {
    await Hardware.instance.setSpeakerphoneOn(enabled);
  }

  /// gets the current speakerphone status.
  bool get isSpeakerphoneOn => Hardware.instance.speakerOn ?? false;

  /// sets the volume for remote audio tracks.
  void setVolume(double volume) {
    if (_room == null) return;
    for (var participant in _room!.remoteParticipants.values) {
      for (var track in participant.audioTrackPublications) {
        final t = track.track;
        if (t is RemoteAudioTrack) {
          try {
            // ignore: undefined_method (to be safe)
            (t as dynamic).setVolume(volume);
          } catch (_) {
            // silently ignore if not supported by the specific version
          }
        }
      }
    }
  }

  /// pauses all audio tracks (user and agent).
  Future<void> pause() async {
    if (_room == null) return;
    
    // 1. mute local user
    await setMicrophoneMuted(true);
    
    // 2. unsubscribe from remote audio tracks to stop data flow
    for (var participant in _room!.remoteParticipants.values) {
      for (var track in participant.audioTrackPublications) {
        if (track.kind == TrackType.AUDIO) {
          // This is a final property in some versions, but we can use the 
          // dedicated method if available or dynamic fallback.
          try {
            // ignore: undefined_method (to be safe)
            (track as dynamic).unsubscribe();
          } catch (_) {}
        }
      }
    }
  }

  /// Resumes all audio tracks.
  Future<void> resume() async {
    if (_room == null) return;
    
    // 1. unmute local user
    await setMicrophoneMuted(false);
    
    // 2. resubscribe to remote audio tracks
    for (var participant in _room!.remoteParticipants.values) {
      for (var track in participant.audioTrackPublications) {
        if (track.kind == TrackType.AUDIO) {
          try {
            // ignore: undefined_method (To be safe)
            (track as dynamic).subscribe();
          } catch (_) {}
        }
      }
    }
  }

  /// sends a DTMF digit to the agent.
  void sendDTMF(String digit) {
    final localParticipant = _room?.localParticipant;
    if (localParticipant == null) return;

    final code = _dtmfMap[digit];
    if (code != null) {
      // implement native DTMF once supported in livekit_client Flutter
      // localParticipant.publishDtmf(code, digit);
      debugPrint('[HamsaSDK] DTMF $digit (code: $code) requested but not yet implemented in this version.');
    }
  }

  static const Map<String, int> _dtmfMap = {
    '0': 0, '1': 1, '2': 2, '3': 3, '4': 4,
    '5': 5, '6': 6, '7': 7, '8': 8, '9': 9,
    '*': 10, '#': 11,
  };
}
