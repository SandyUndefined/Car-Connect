import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../room/room_controller.dart';

class CallScreen extends ConsumerWidget {
  const CallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(roomControllerProvider);
    final ctrl = ref.read(roomControllerProvider.notifier);

    final tiles = <Widget>[];
    if (st.localRenderer != null) {
      tiles.add(_VideoTile(label: "You", renderer: st.localRenderer!, mirror: true));
    }
    for (final p in st.peers) {
      tiles.add(_VideoTile(label: p.userId, renderer: p.renderer));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Mesh Call')),
      body: Column(
        children: [
          Expanded(
            child: GridView.count(
              crossAxisCount: (tiles.length <= 2) ? 1 : 2,
              children: tiles,
            ),
          ),
          SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(st.micOn ? Icons.mic : Icons.mic_off),
                  onPressed: ctrl.toggleMic,
                ),
                IconButton(
                  icon: Icon(st.camOn ? Icons.videocam : Icons.videocam_off),
                  onPressed: ctrl.toggleCam,
                ),
                ElevatedButton.icon(
                  onPressed: ctrl.leave,
                  icon: const Icon(Icons.call_end),
                  label: const Text("End"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  final String label;
  final RTCVideoRenderer renderer;
  final bool mirror;
  const _VideoTile({required this.label, required this.renderer, this.mirror = false, super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RTCVideoView(renderer, mirror: mirror, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
        Positioned(
          left: 12, bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.black54,
            child: Text(label, style: const TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }
}
