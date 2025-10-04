import 'package:flutter_webrtc/flutter_webrtc.dart';

class Peer {
  final String userId;
  final String socketId;
  final RTCPeerConnection pc;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  MediaStream? remoteStream;

  Peer({required this.userId, required this.socketId, required this.pc});

  Future<void> initRenderer() async => renderer.initialize();

  Future<void> dispose() async {
    try { await renderer.dispose(); } catch (_) {}
    try { await remoteStream?.dispose(); } catch (_) {}
    try { await pc.close(); } catch (_) {}
  }
}
