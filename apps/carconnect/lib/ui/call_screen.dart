import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../room/room_controller.dart';
import '../room/sfu_controller.dart';

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  @override
  void initState() {
    super.initState();
    ref.listen<RoomState>(roomControllerProvider, (prev, next) {
      final previous = prev?.removedByHostEventId ?? 0;
      final current = next.removedByHostEventId;
      if (current > previous) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await ref.read(sfuControllerProvider.notifier).stop();
          await ref.read(roomControllerProvider.notifier).leave();
          if (!mounted) return;
          final navigator = Navigator.of(context);
          navigator.popUntil((route) => route.isFirst);
          if (!mounted) return;
          ScaffoldMessenger.of(navigator.context).showSnackBar(
            const SnackBar(content: Text('You were removed by the host')),
          );
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(roomControllerProvider);
    final sfuState = ref.watch(sfuControllerProvider);
    final sfuPeers = sfuState.peers;
    final ctrl = ref.read(roomControllerProvider.notifier);
    final activeSpeaker = sfuState.activeSpeakerUserId;
    final role = _tokenRole(st.token);
    final isHost = role == 'host';

    final tiles = <Widget>[];
    if (st.localRenderer != null) {
      tiles.add(_VideoTile(
        label: "You",
        renderer: st.localRenderer!,
        mirror: true,
        highlight: activeSpeaker != null && activeSpeaker == st.selfUserId,
        isHost: isHost,
      ));
    }
    for (final p in st.peers) {
      tiles.add(_VideoTile(
        label: p.userId,
        renderer: p.renderer,
        highlight: activeSpeaker != null && activeSpeaker == p.userId,
      ));
    }
    for (final v in sfuPeers) {
      tiles.add(_VideoTile(
        label: v.userId,
        renderer: v.renderer,
        highlight: activeSpeaker != null && activeSpeaker == v.userId,
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh Call'),
        actions: [
          if (isHost)
            PopupMenuButton<_HostAction>(
              onSelected: (action) => _onHostAction(action, ctrl, st.roomLocked),
              itemBuilder: (context) => [
                const PopupMenuItem<_HostAction>(
                  value: _HostAction.muteAll,
                  child: Text('Mute all'),
                ),
                PopupMenuItem<_HostAction>(
                  value: _HostAction.toggleLock,
                  child: Text(st.roomLocked ? 'Unlock room' : 'Lock room'),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          if (st.roomLocked)
            Container(
              width: double.infinity,
              color: Colors.orange.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: const Row(
                children: [
                  Icon(Icons.lock, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Room is locked. New participants cannot join.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
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

  Future<void> _onHostAction(_HostAction action, RoomController ctrl, bool isLocked) async {
    try {
      switch (action) {
        case _HostAction.muteAll:
          await ctrl.muteAllParticipants();
          break;
        case _HostAction.toggleLock:
          if (isLocked) {
            await ctrl.unlockRoom();
          } else {
            await ctrl.lockRoom();
          }
          break;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: $e')),
      );
    }
  }

  String? _tokenRole(String? token) {
    final payload = _decodeTokenPayload(token);
    final role = payload?['role'];
    return role is String ? role : null;
  }

  Map<String, dynamic>? _decodeTokenPayload(String? token) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final dynamic payload = jsonDecode(decoded);
      if (payload is Map<String, dynamic>) {
        return payload;
      }
    } catch (_) {}
    return null;
  }
}

enum _HostAction { muteAll, toggleLock }

class _VideoTile extends StatelessWidget {
  final String label;
  final RTCVideoRenderer renderer;
  final bool mirror;
  final CallStats? stats;
  final bool highlight;
  final bool isHost;
  const _VideoTile({
    required this.label,
    required this.renderer,
    this.stats,
    this.mirror = false,
    this.highlight = false,
    this.isHost = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = highlight ? Colors.greenAccent : Colors.transparent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            RTCVideoView(
              renderer,
              mirror: mirror,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            ),
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label, style: const TextStyle(color: Colors.white)),
                        if (isHost)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.workspace_premium, color: Colors.amber, size: 16),
                          ),
                      ],
                    ),
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
        ),
      ),
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
