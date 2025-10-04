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

  RoomState({
    this.roomId,
    this.token,
    this.micOn = true,
    this.camOn = true,
    this.peers = const [],
    this.localRenderer,
  });

  RoomState copyWith({
    String? roomId,
    String? token,
    bool? micOn,
    bool? camOn,
    List<Peer>? peers,
    RTCVideoRenderer? localRenderer,
  }) => RoomState(
        roomId: roomId ?? this.roomId,
        token: token ?? this.token,
        micOn: micOn ?? this.micOn,
        camOn: camOn ?? this.camOn,
        peers: peers ?? this.peers,
        localRenderer: localRenderer ?? this.localRenderer,
      );
}

class RoomController extends Notifier<RoomState> {
  late final SignalingRest _rest;
  SignalingSocket? _sock;
  final RtcManager _rtc = RtcManager();
  final String _selfId = const Uuid().v4(); // userId

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
    state = RoomState();
  }
}
