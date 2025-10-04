import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class RtcManager {
  MediaStream? localStream;
  final Map<String, PeerConnectionState> _pcStates = {};

  Future<RTCPeerConnection> createPeerConnectionWithConfig(List<Map<String, dynamic>> iceServers) async {
    final Map<String, dynamic> config = {
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    };
    final pc = await createPeerConnection(config);
    return pc;
  }

  Future<MediaStream> ensureLocal({bool video = true, bool audio = true}) async {
    if (localStream != null) return localStream!;
    final mediaConstraints = {
      'audio': audio,
      'video': video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
              'frameRate': {'ideal': 30},
            }
          : false,
    };
    localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    return localStream!;
  }

  // Try enabling simulcast on the video sender (best-effort)
  Future<void> tryEnableSimulcast(RTCRtpSender sender) async {
    final params = await sender.getParameters();
    final encodings = params.encodings;
    if (encodings == null || encodings.isEmpty) {
      params.encodings = [
        RTCRtpEncoding(rid: 'f', maxBitrate: 1_500_000, numTemporalLayers: 2),
        RTCRtpEncoding(rid: 'h', maxBitrate: 800_000, scaleResolutionDownBy: 2, numTemporalLayers: 2),
        RTCRtpEncoding(rid: 'q', maxBitrate: 250_000, scaleResolutionDownBy: 4, numTemporalLayers: 2),
      ];
      await sender.setParameters(params);
    }
  }

  Future<void> dispose() async {
    try { await localStream?.getTracks().forEach((t) => t.stop()); } catch (_) {}
    try { await localStream?.dispose(); } catch (_) {}
    localStream = null;
  }
}
