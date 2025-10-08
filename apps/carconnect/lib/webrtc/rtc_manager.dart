import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class RtcManager {
  MediaStream? localStream;

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
    final params = await _getSenderParameters(sender);
    if (params == null) return;
    final encodings = params.encodings;
    if (encodings != null && encodings.isNotEmpty) return;
    params.encodings = [
      RTCRtpEncoding(rid: 'f', maxBitrate: 1500000, numTemporalLayers: 2),
      RTCRtpEncoding(rid: 'h', maxBitrate: 800000, scaleResolutionDownBy: 2, numTemporalLayers: 2),
      RTCRtpEncoding(rid: 'q', maxBitrate: 250000, scaleResolutionDownBy: 4, numTemporalLayers: 2),
    ];
    await sender.setParameters(params);
  }

  Future<void> dispose() async {
    final tracks = localStream?.getTracks() ?? const <MediaStreamTrack>[];
    for (final track in tracks) {
      try {
        await Future.sync(track.stop);
      } catch (_) {}
    }
    try { await localStream?.dispose(); } catch (_) {}
    localStream = null;
  }

  Future<RTCRtpParameters?> _getSenderParameters(RTCRtpSender sender) async {
    try {
      final dynamic dynamicSender = sender;
      // ignore: avoid_dynamic_calls
      final dynamic params = await dynamicSender.getParameters();
      if (params is RTCRtpParameters) {
        return params;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
