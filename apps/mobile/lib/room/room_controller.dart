import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import '../api/signaling_rest.dart';
import '../webrtc/signaling_socket.dart';
import '../webrtc/rtc_manager.dart';
import '../webrtc/peer.dart';
import '../env.dart';

final roomControllerProvider = NotifierProvider<RoomController, RoomState>(RoomController.new);

class RoomState {
  final String? roomId;
  final String? token;
  final bool micOn;
  final bool camOn;
  final List<Peer> peers; // remote peers
  final RTCVideoRenderer? localRenderer;
  final Map<String, CallStats> stats;

  RoomState({
    this.roomId,
    this.token,
    this.micOn = true,
    this.camOn = true,
    this.peers = const [],
    this.localRenderer,
    this.stats = const {},
  });

  RoomState copyWith({
    String? roomId,
    String? token,
    bool? micOn,
    bool? camOn,
    List<Peer>? peers,
    RTCVideoRenderer? localRenderer,
    Map<String, CallStats>? stats,
  }) => RoomState(
        roomId: roomId ?? this.roomId,
        token: token ?? this.token,
        micOn: micOn ?? this.micOn,
        camOn: camOn ?? this.camOn,
        peers: peers ?? this.peers,
        localRenderer: localRenderer ?? this.localRenderer,
        stats: stats ?? this.stats,
      );
}

class CallStats {
  final double? outboundKbps;
  final double? inboundKbps;
  final double? rttMs;
  final double? packetLossPercent;

  const CallStats({
    this.outboundKbps,
    this.inboundKbps,
    this.rttMs,
    this.packetLossPercent,
  });
}

class RoomController extends Notifier<RoomState> {
  late final SignalingRest _rest;
  SignalingSocket? _sock;
  final RtcManager _rtc = RtcManager();
  final String _selfId = const Uuid().v4(); // userId
  Timer? _statsTimer;
  bool _collectingStats = false;
  final Map<String, _BitrateSnapshot> _previousBitrates = {};

  @override
  RoomState build() {
    _rest = SignalingRest(ref.read(dioProvider));
    return RoomState();
  }

  Future<void> createRoom() async {
    final (roomId, token) = await _rest.createRoom(_selfId, mode: "mesh");
    state = state.copyWith(roomId: roomId, token: token);
    await _connectSocketAndMedia();
  }

  Future<void> joinRoom(String roomId) async {
    final token = await _rest.joinRoom(roomId, _selfId);
    state = state.copyWith(roomId: roomId, token: token);
    await _connectSocketAndMedia();
  }

  Future<void> _connectSocketAndMedia() async {
    // Local media
    final stream = await _rtc.ensureLocal(video: true, audio: true);
    final localRenderer = RTCVideoRenderer();
    await localRenderer.initialize();
    localRenderer.srcObject = stream;
    state = state.copyWith(localRenderer: localRenderer);

    // TURN
    final ice = await _rest.getTurnIceServers(_selfId);

    // Socket
    _sock?.dispose();
    _sock = SignalingSocket(Env.signalingBase, state.token!);
    _sock!.connect(
      onConnect: (_) {},
      onDisconnect: () {},
      onSignal: _onSignal,
      onJoined: _onJoined,
      onLeft: _onLeft,
      onMute: (_) {},
      onVideoToggle: (_) {},
      onAudioLevel: (_) {},
    );

    // For mesh: we will create pc per remote when we see participantJoined or when we want to call everyone.
    // Act as polite peer: wait for remote offer if they initiate; otherwise create offer to new remote.
    _startStatsTimer();
  }

  Future<Peer> _createPeer(String remoteUserId, String remoteSocketId, List<Map<String, dynamic>> ice) async {
    final pc = await _rtc.createPeerConnectionWithConfig(ice);
    final peer = Peer(userId: remoteUserId, socketId: remoteSocketId, pc: pc);
    await peer.initRenderer();

    // Local -> add tracks
    final local = _rtc.localStream!;
    for (final t in local.getTracks()) {
      final sender = await pc.addTrack(t, local);
      if (t.kind == 'video') {
        await _rtc.tryEnableSimulcast(sender); // best effort
      }
    }

    // Remote stream handling
    pc.onTrack = (RTCTrackEvent e) async {
      if (e.streams.isNotEmpty) {
        peer.remoteStream = e.streams.first;
        peer.renderer.srcObject = peer.remoteStream;
        state = state.copyWith(peers: [...state.peers.where((p) => p.socketId != peer.socketId), peer]);
      }
    };

    // ICE candidates -> send via socket
    pc.onIceCandidate = (RTCIceCandidate c) {
      _sock?.emitSignal({
        'toSocketId': remoteSocketId,
        'data': {
          'type': 'candidate',
          'candidate': c.toMap(),
        }
      });
    };

    return peer;
  }

  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _collectStats();
    });
    _collectStats();
  }

  Future<void> _collectStats() async {
    if (_collectingStats) return;
    _collectingStats = true;
    try {
      final Map<String, CallStats> peerStats = {};
      double? localOutboundSum;
      double? localInboundSum;
      final List<double> localRtts = [];
      final List<double> localLosses = [];

      for (final peer in state.peers) {
        final stats = await _statsForPeer(peer);
        if (stats == null) continue;
        peerStats[peer.userId] = stats;
        if (stats.outboundKbps != null) {
          localOutboundSum = (localOutboundSum ?? 0) + stats.outboundKbps!;
        }
        if (stats.inboundKbps != null) {
          localInboundSum = (localInboundSum ?? 0) + stats.inboundKbps!;
        }
        if (stats.rttMs != null) {
          localRtts.add(stats.rttMs!);
        }
        if (stats.packetLossPercent != null) {
          localLosses.add(stats.packetLossPercent!);
        }
      }

      if (localOutboundSum != null ||
          localInboundSum != null ||
          localRtts.isNotEmpty ||
          localLosses.isNotEmpty) {
        peerStats['local'] = CallStats(
          outboundKbps: localOutboundSum,
          inboundKbps: localInboundSum,
          rttMs: localRtts.isNotEmpty ? localRtts.reduce((a, b) => a + b) / localRtts.length : null,
          packetLossPercent: localLosses.isNotEmpty ? localLosses.reduce((a, b) => a + b) / localLosses.length : null,
        );
      }

      if (!_mapsEqual(state.stats, peerStats)) {
        state = state.copyWith(stats: Map.unmodifiable(peerStats));
      }
    } finally {
      _collectingStats = false;
    }
  }

  Future<CallStats?> _statsForPeer(Peer peer) async {
    try {
      final reports = await peer.pc.getStats();
      double? outboundTotal;
      double? inboundTotal;
      final List<double> rttValues = [];
      final List<double> lossValues = [];

      for (final report in reports) {
        switch (report.type) {
          case 'outbound-rtp':
            final bitrate = _bitrateForReport(peer.socketId, report, 'bytesSent');
            if (bitrate != null) {
              outboundTotal = (outboundTotal ?? 0) + bitrate;
            }
            break;
          case 'inbound-rtp':
            final bitrate = _bitrateForReport(peer.socketId, report, 'bytesReceived');
            if (bitrate != null) {
              inboundTotal = (inboundTotal ?? 0) + bitrate;
            }
            final loss = _lossForReport(report);
            if (loss != null) {
              lossValues.add(loss);
            }
            break;
          case 'candidate-pair':
            final rtt = _rttForReport(report);
            if (rtt != null) {
              rttValues.add(rtt);
            }
            break;
          case 'remote-inbound-rtp':
            final rtt = _rttFromRemoteInbound(report);
            if (rtt != null) {
              rttValues.add(rtt);
            }
            final loss = _lossForRemoteInbound(report);
            if (loss != null) {
              lossValues.add(loss);
            }
            break;
        }
      }

      if (outboundTotal == null && inboundTotal == null && rttValues.isEmpty && lossValues.isEmpty) {
        return null;
      }

      return CallStats(
        outboundKbps: outboundTotal,
        inboundKbps: inboundTotal,
        rttMs: rttValues.isNotEmpty ? rttValues.reduce((a, b) => a + b) / rttValues.length : null,
        packetLossPercent: lossValues.isNotEmpty ? lossValues.reduce((a, b) => a + b) / lossValues.length : null,
      );
    } catch (_) {
      return null;
    }
  }

  double? _bitrateForReport(String socketId, RTCStatsReport report, String bytesKey) {
    final bytes = _numFromDynamic(report.values[bytesKey]);
    final timestamp = _timestampFromReport(report);
    if (bytes == null || timestamp == null) return null;
    final key = '$socketId:${report.id}:$bytesKey';
    final snapshot = _previousBitrates[key];
    _previousBitrates[key] = _BitrateSnapshot(bytes, timestamp);
    if (snapshot == null) return null;
    final deltaBytes = bytes - snapshot.bytes;
    final deltaTimeMs = timestamp - snapshot.timestamp;
    if (deltaBytes <= 0 || deltaTimeMs <= 0) return null;
    final bitsPerSecond = (deltaBytes * 8 * 1000) / deltaTimeMs;
    return bitsPerSecond / 1000; // kbps
  }

  double? _rttForReport(RTCStatsReport report) {
    final stateValue = report.values['state'];
    if (stateValue != 'succeeded') return null;
    final rttSeconds = _numFromDynamic(report.values['currentRoundTripTime']);
    if (rttSeconds == null) return null;
    return rttSeconds * 1000;
  }

  double? _rttFromRemoteInbound(RTCStatsReport report) {
    final rttSeconds = _numFromDynamic(report.values['roundTripTime']);
    if (rttSeconds == null) return null;
    return rttSeconds * 1000;
  }

  double? _lossForReport(RTCStatsReport report) {
    final lost = _numFromDynamic(report.values['packetsLost']);
    final received = _numFromDynamic(report.values['packetsReceived']);
    if (lost == null || received == null) return null;
    final total = lost + received;
    if (total <= 0) return null;
    return (lost / total) * 100;
  }

  double? _lossForRemoteInbound(RTCStatsReport report) {
    final lost = _numFromDynamic(report.values['packetsLost']);
    final sent = _numFromDynamic(report.values['packetsSent']);
    if (lost == null || sent == null) return null;
    final total = lost + sent;
    if (total <= 0) return null;
    return (lost / total) * 100;
  }

  double? _timestampFromReport(RTCStatsReport report) {
    final timestamp = report.timestamp;
    if (timestamp is num) {
      return timestamp.toDouble();
    }
    if (timestamp is String) {
      return double.tryParse(timestamp);
    }
    return null;
  }

  double? _numFromDynamic(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  bool _mapsEqual(Map<String, CallStats> a, Map<String, CallStats> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null) return false;
      if (!_statsEqual(entry.value, other)) return false;
    }
    return true;
  }

  bool _statsEqual(CallStats a, CallStats b) {
    return _closeTo(a.outboundKbps, b.outboundKbps) &&
        _closeTo(a.inboundKbps, b.inboundKbps) &&
        _closeTo(a.rttMs, b.rttMs) &&
        _closeTo(a.packetLossPercent, b.packetLossPercent);
  }

  bool _closeTo(double? a, double? b) {
    if (a == null || b == null) return a == b;
    return (a - b).abs() < 0.01;
  }

  Future<void> _onJoined(Map<String, dynamic> data) async {
    // someone else joined the room; we (existing) initiate offer
    final remoteUserId = data['userId'] as String;
    final remoteSocketId = data['socketId'] as String;
    if (remoteUserId == _selfId) return;

    final ice = await _rest.getTurnIceServers(_selfId);
    final peer = await _createPeer(remoteUserId, remoteSocketId, ice);

    final offer = await peer.pc.createOffer({'offerToReceiveVideo': 1, 'offerToReceiveAudio': 1});
    await peer.pc.setLocalDescription(offer);

    _sock?.emitSignal({
      'toSocketId': remoteSocketId,
      'data': {'type': 'offer', 'sdp': offer.sdp, 'sdpType': offer.type}
    });

    state = state.copyWith(peers: [...state.peers, peer]);
  }

  Future<void> _onLeft(Map<String, dynamic> data) async {
    final socketId = data['socketId'] as String;
    final peer = state.peers.firstWhere((p) => p.socketId == socketId, orElse: () => null as dynamic);
    if (peer != null) {
      await peer.dispose();
      state = state.copyWith(peers: state.peers.where((p) => p.socketId != socketId).toList());
      _clearSnapshotsForPeer(socketId);
    }
  }

  Future<void> _onSignal(Map<String, dynamic> payload) async {
    final fromSocketId = payload['fromSocketId'] as String;
    final fromUserId = payload['fromUserId'] as String;
    final data = Map<String, dynamic>.from(payload['data']);

    // find or create peer
    var peer = state.peers.firstWhere((p) => p.socketId == fromSocketId, orElse: () => null as dynamic);

    if (data['type'] == 'offer') {
      if (peer == null) {
        final ice = await _rest.getTurnIceServers(_selfId);
        peer = await _createPeer(fromUserId, fromSocketId, ice);
        state = state.copyWith(peers: [...state.peers, peer]);
      }
      await peer.pc.setRemoteDescription(RTCSessionDescription(data['sdp'], 'offer'));
      final answer = await peer.pc.createAnswer();
      await peer.pc.setLocalDescription(answer);
      _sock?.emitSignal({
        'toSocketId': fromSocketId,
        'data': {'type': 'answer', 'sdp': answer.sdp, 'sdpType': answer.type}
      });
    } else if (data['type'] == 'answer') {
      if (peer != null) {
        await peer.pc.setRemoteDescription(RTCSessionDescription(data['sdp'], 'answer'));
      }
    } else if (data['type'] == 'candidate') {
      if (peer != null) {
        final cMap = Map<String, dynamic>.from(data['candidate']);
        await peer.pc.addCandidate(RTCIceCandidate(cMap['candidate'], cMap['sdpMid'], cMap['sdpMLineIndex']));
      }
    }
  }

  void toggleMic() {
    final enabled = !state.micOn;
    _rtc.localStream?.getAudioTracks().forEach((t) => t.enabled = enabled);
    _sock?.emitMute(!enabled);
    state = state.copyWith(micOn: enabled);
  }

  void toggleCam() {
    final enabled = !state.camOn;
    _rtc.localStream?.getVideoTracks().forEach((t) => t.enabled = enabled);
    _sock?.emitVideoToggle(enabled);
    state = state.copyWith(camOn: enabled);
  }

  Future<void> leave() async {
    _sock?.leaveRoom();
    for (final p in state.peers) { await p.dispose(); }
    await _rtc.dispose();
    _sock?.dispose();
    _statsTimer?.cancel();
    _previousBitrates.clear();
    state = RoomState();
  }

  void _clearSnapshotsForPeer(String socketId) {
    _previousBitrates.removeWhere((key, _) => key.startsWith('$socketId:'));
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    super.dispose();
  }
}

class _BitrateSnapshot {
  final double bytes;
  final double timestamp;
  _BitrateSnapshot(num bytes, double timestamp)
      : bytes = bytes.toDouble(),
        timestamp = timestamp;
}
