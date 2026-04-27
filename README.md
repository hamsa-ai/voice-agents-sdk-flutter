# Hamsa Voice Flutter SDK

The official Flutter SDK for [Hamsa AI](https://tryhamsa.com). Build high-performance, low-latency AI voice agents into your Flutter applications.

## Features

- 🚀 **Low Latency**: Optimized for real-time voice interaction.
- 🎙️ **Rich Control**: Pause/Resume, Mute, Speakerphone, and Volume control.
- ⌨️ **DTMF Support**: Interact with IVR systems.
- 📊 **Logging**: Built-in API and connection logging for debugging.
- 🎨 **Flexible UI**: Agnostic SDK—build your own UI or use our Orb design patterns.

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  hamsa_voice_flutter:
    git:
      url: https://github.com/hamsa-ai/voice-agents-sdk-flutter.git
```

## Getting Started

### 1. Initialize the Agent

```dart
import 'package:hamsa_voice_flutter/hamsa_voice_flutter.dart';

final agent = HamsaVoiceAgent(apiKey: 'YOUR_HAMSA_API_KEY');
```

### 2. Start a Session

```dart
await agent.start('YOUR_AGENT_ID');
```

### 3. Listen to Events

```dart
agent.onConnectionStatusChanged = (status) {
  print('Connection: $status');
};

agent.onAgentStateChanged = (state) {
  print('Agent is: $state');
};
```

### 4. Control the Session

```dart
// Mute microphone
await agent.setMuted(true);

// Toggle speakerphone
await agent.setSpeakerphoneOn(true);

// Pause the AI (mutes both sides)
await agent.pause();

// Resume
await agent.resume();

// End call
await agent.stop();
```

## Permissions

Ensure you have microphone permissions configured in your `AndroidManifest.xml` and `Info.plist`.

### Android
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

### iOS
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to the microphone for AI voice interaction.</string>
```

## License

MIT License. See `LICENSE` for details.
