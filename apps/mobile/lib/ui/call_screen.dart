import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../room/room_controller.dart';
import '../room/sfu_controller.dart';

class CallScreen extends ConsumerWidget {
  const CallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(roomControllerProvider);
    final sfuPeers = ref.watch(sfuControllerProvider);
    final ctrl = ref.read(roomControllerProvider.notifier);

    final tiles = <Widget>[];
    if (st.localRenderer != null) {
      tiles.add(_VideoTile(
        label: "You",
        renderer: st.localRenderer!,
        mirror: true,
      ));
    }
    for (final p in st.peers) {
      tiles.add(_VideoTile(
        label: p.userId,
        renderer: p.renderer,
      ));
    }
    for (final v in sfuPeers) {
      tiles.add(_VideoTile(
        label: v.userId,
        renderer: v.renderer,
      ));
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
                  onPressed: () async {
                    await ref.read(sfuControllerProvider.notifier).stop();
                    await ctrl.leave();
                  },
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
  final CallStats? stats;
  const _VideoTile({required this.label, required this.renderer, this.stats, this.mirror = false, super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RTCVideoView(renderer, mirror: mirror, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
        Positioned(
          left: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(color: Colors.white)),
                if (stats != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _formatStats(stats!),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatStats(CallStats stats) {
    final outbound = _formatKbps(stats.outboundKbps);
    final inbound = _formatKbps(stats.inboundKbps);
    final rtt = _formatMs(stats.rttMs);
    final loss = _formatPercent(stats.packetLossPercent);
    return '↑$outbound ↓$inbound kbps / RTT $rtt ms / Loss $loss%';
  }

  String _formatKbps(double? value) {
    if (value == null) return '-';
    if (value >= 100) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  String _formatMs(double? value) {
    if (value == null) return '-';
    if (value >= 100) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  String _formatPercent(double? value) {
    if (value == null) return '-';
    return value.toStringAsFixed(1);
  }
}
