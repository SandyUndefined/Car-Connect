import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'env.dart';
import 'webrtc/signaling_client.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

final signalingClientProvider = Provider<SignalingClient>((ref) {
  return SignalingClient(Env.signalingBase);
});

final lastMessageProvider = StateProvider<String?>((ref) => null);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Car Connect',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue), useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final TextEditingController _hostController = TextEditingController(text: 'host-1');
  final TextEditingController _roomController = TextEditingController();

  @override
  void dispose() {
    _hostController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    final client = ref.read(signalingClientProvider);
    final notifier = ref.read(lastMessageProvider.notifier);
    try {
      final response = await client.createRoom(_hostController.text);
      final message = 'Created room: ${jsonEncode(response)}';
      notifier.state = message;
      // ignore: avoid_print
      print(message);
      _roomController.text = response['id']?.toString() ?? _roomController.text;
    } catch (error, stackTrace) {
      final message = 'Failed to create room: $error';
      notifier.state = message;
      // ignore: avoid_print
      print(message);
      // ignore: avoid_print
      print(stackTrace);
    }
  }

  Future<void> _joinRoom() async {
    final client = ref.read(signalingClientProvider);
    final notifier = ref.read(lastMessageProvider.notifier);
    try {
      final response = await client.joinRoom(_roomController.text);
      final message = 'Joined room: ${jsonEncode(response)}';
      notifier.state = message;
      // ignore: avoid_print
      print(message);
    } catch (error, stackTrace) {
      final message = 'Failed to join room: $error';
      notifier.state = message;
      // ignore: avoid_print
      print(message);
      // ignore: avoid_print
      print(stackTrace);
    }
  }

  Future<void> _fetchTurnCredentials() async {
    final client = ref.read(signalingClientProvider);
    final notifier = ref.read(lastMessageProvider.notifier);
    try {
      final response = await client.turnCred();
      final message = 'Fetched TURN credentials: ${jsonEncode(response)}';
      notifier.state = message;
      // ignore: avoid_print
      print(message);
    } catch (error, stackTrace) {
      final message = 'Failed to fetch TURN credentials: $error';
      notifier.state = message;
      // ignore: avoid_print
      print(message);
      // ignore: avoid_print
      print(stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastMessage = ref.watch(lastMessageProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Car Connect Signaling'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(labelText: 'Host ID'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _createRoom,
                    child: const Text('Create Room'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _fetchTurnCredentials,
                    child: const Text('Get TURN Creds'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _roomController,
              decoration: const InputDecoration(labelText: 'Room ID'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _joinRoom,
                child: const Text('Join Room'),
              ),
            ),
            const SizedBox(height: 24),
            if (lastMessage != null) ...[
              const Text('Last message:'),
              const SizedBox(height: 8),
              Text(lastMessage),
            ],
          ],
        ),
      ),
    );
  }
}
