import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../sfu/sfu_client.dart';
import '../api/signaling_rest.dart';
import '../webrtc/rtc_manager.dart';
import '../env.dart';

class SfuPeerView {
  final String userId;
  final String producerId;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  SfuPeerView({required this.userId, required this.producerId});
  Future<void> dispose() async => renderer.dispose();
}

final sfuControllerProvider = NotifierProvider<SfuController, List<SfuPeerView>>(SfuController.new);

class SfuController extends Notifier<List<SfuPeerView>> {
  final _rtc = RtcManager();
  SfuClient? _sfu;
  RTCPeerConnection? _sendPc;
  RTCPeerConnection? _recvPc;
  RTCRtpSender? _videoSender;
  List<Map<String, dynamic>> _ice = [];
  String? _token;

  @override
  List<SfuPeerView> build() => [];

  Future<void> start(String token) async {
    _token = token;
    // Fetch TURN for publisher reliability (optional if SFU is public).
    final rest = SignalingRest(ref.read(dioProvider));
    _ice = await rest.getTurnIceServers("uplink");

    _sfu?.dispose();
    _sfu = SfuClient("${Env.signalingBase.replaceFirst(':8080', ':9090')}", token);
    _sfu!.connect();

    // --- Step 1: get router caps
    final routerCaps = Completer<dynamic>();
    _sfu!.emitAck("sfu.getRouterRtpCapabilities", {}, (resp) => routerCaps.complete(resp));
    final rtpCaps = await routerCaps.future;

    // --- Step 2: create SEND transport (publisher)
    final sendInfo = await _emitAck("sfu.createWebRtcTransport", {"direction":"send"});
    _sendPc = await _createPc(_ice);
    await _sendPc!.setConfiguration({'iceServers': _ice});

    // Wire local media
    final local = await _rtc.ensureLocal(video: true, audio: true);
    for (final t in local.getTracks()) {
      final sender = await _sendPc!.addTrack(t, local);
      if (t.kind == 'video') _videoSender = sender;
    }

    // ICE candidates from PC → ignored (mediasoup uses DTLS/ICE via connectTransport)
    _sendPc!.onIceCandidate = (_) {};

    // Create local offer and set
    final offer = await _sendPc!.createOffer();
    await _sendPc!.setLocalDescription(offer);

    // Connect transport at DTLS phase
    await _emitAck("sfu.connectTransport", {
      "transportId": sendInfo["id"],
      "dtlsParameters": (await _sendPc!.getLocalDescription())!.toMap()["sdp"]
    }, raw: true); // we'll send SDP in raw to server which doesn't parse; just a placeholder connect ack

    // Produce audio/video using native API: we’ll hand rtpParameters via built-in getSenders() SDP.
    // For simplicity, we request server to accept production after answer.
    // (In a full client, you'd extract rtpParameters programmatically. For MVP we shortcut using offer->answer.)

    // --- Step 3: create RECV transport (downlinks)
    final recvInfo = await _emitAck("sfu.createWebRtcTransport", {"direction":"recv"});
    _recvPc = await _createPc(_ice);
    _recvPc!.onIceCandidate = (_) {};
    final recvOffer = await _recvPc!.createOffer();
    await _recvPc!.setLocalDescription(recvOffer);
    await _emitAck("sfu.connectTransport", {
      "transportId": recvInfo["id"],
      "dtlsParameters": (await _recvPc!.getLocalDescription())!.toMap()["sdp"]
    }, raw: true);

    // Listen for new producers to consume:
    _sfu!.on("sfu.newProducer", (data) async {
      final producerId = data["producerId"];
      final resp = await _emitAck("sfu.consume", {
        "producerId": producerId,
        "rtpCapabilities": rtpCaps
      });
      // Set remote description if needed; with Flutter we bind track via onTrack
    });

    // Hook remote tracks
    _recvPc!.onTrack = (RTCTrackEvent e) async {
      if (e.streams.isEmpty) return;
      final v = SfuPeerView(userId: "unknown", producerId: "p");
      await v.renderer.initialize();
      v.renderer.srcObject = e.streams.first;
      state = [...state, v];
    };
  }

  Future<RTCPeerConnection> _createPc(List<Map<String, dynamic>> ice) async {
    final pc = await createPeerConnection({
      "iceServers": ice,
      "sdpSemantics": "unified-plan",
      "bundlePolicy": "max-bundle",
    });
    return pc;
  }

  Future<dynamic> _emitAck(String evt, dynamic data, {bool raw = false}) {
    final c = Completer<dynamic>();
    _sfu!.emitAck(evt, data, (resp) => c.complete(resp));
    return c.future;
  }

  Future<void> stop() async {
    for (final v in state) { await v.dispose(); }
    state = [];
    try { await _sendPc?.close(); } catch (_) {}
    try { await _recvPc?.close(); } catch (_) {}
    _sendPc = null; _recvPc = null; _videoSender = null;
    _sfu?.dispose(); _sfu = null;
    await _rtc.dispose();
  }
}
