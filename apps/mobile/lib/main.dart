import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/call_screen.dart';
import 'room/room_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: App()));
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RTC Mesh Demo',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const Home(),
    );
  }
}

class Home extends ConsumerWidget {
  const Home({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(roomControllerProvider.notifier);
    final idCtrl = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: () async {
                await ctrl.createRoom();
                if (context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const CallScreen()));
              },
              child: const Text('Create Room'),
            ),
            const SizedBox(height: 12),
            TextField(controller: idCtrl, decoration: const InputDecoration(labelText: 'Room ID')),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                final roomId = idCtrl.text.trim();
                if (roomId.isEmpty) return;
                await ctrl.joinRoom(roomId);
                if (context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const CallScreen()));
              },
              child: const Text('Join Room'),
            ),
          ],
        ),
      ),
    );
  }
}
