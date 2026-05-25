import 'package:flutter/material.dart';
import 'package:hamsa_voice_flutter/hamsa_voice_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hamsa SDK Example',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ExampleHomePage(),
    );
  }
}

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key});

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  late final HamsaVoiceAgent _agent;
  String _status = 'Disconnected';

  @override
  void initState() {
    super.initState();
    _agent = HamsaVoiceAgent(apiKey: 'YOUR_API_KEY');
    
    _agent.onConnectionStatusChanged = (status) {
      setState(() {
        _status = status.name;
      });
    };
  }

  void _startCall() async {
    try {
      await _agent.start('YOUR_AGENT_ID');
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    }
  }

  void _endCall() async {
    await _agent.stop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hamsa Voice Example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Status: $_status', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _startCall,
              child: const Text('Start Call'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _endCall,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('End Call', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
