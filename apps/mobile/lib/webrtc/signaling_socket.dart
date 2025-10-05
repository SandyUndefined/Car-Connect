import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;

typedef SignalHandler = void Function(Map<String, dynamic> payload);

class SignalingSocket {
  final String baseUrl;
  final String token;
  IO.Socket? _socket;

  SignalingSocket(this.baseUrl, this.token);

  void connect({
    required void Function(String id) onConnect,
    required void Function() onDisconnect,
    required SignalHandler onSignal,
    required void Function(Map<String, dynamic>) onJoined,
    required void Function(Map<String, dynamic>) onLeft,
    required void Function(Map<String, dynamic>) onMute,
    required void Function(Map<String, dynamic>) onVideoToggle,
    required void Function(Map<String, dynamic>) onAudioLevel,
  }) {
    _socket = IO.io(baseUrl, {
      'transports': ['websocket'],
      'autoConnect': false,
      'auth': {'token': token},
      'forceNew': true,
    });

    _socket!.on('connect', (_) => onConnect(_socket!.id!));
    _socket!.on('disconnect', (_) => onDisconnect());

    _socket!.on('signal', (data) => onSignal(Map<String, dynamic>.from(data)));
    _socket!.on('participantJoined', (data) => onJoined(Map<String, dynamic>.from(data)));
    _socket!.on('participantLeft', (data) => onLeft(Map<String, dynamic>.from(data)));
    _socket!.on('mute', (data) => onMute(Map<String, dynamic>.from(data)));
    _socket!.on('videoToggle', (data) => onVideoToggle(Map<String, dynamic>.from(data)));
    _socket!.on('audioLevel', (data) => onAudioLevel(Map<String, dynamic>.from(data)));

    _socket!.connect();
  }

  void emitSignal(Map<String, dynamic> payload) => _socket?.emit('signal', payload);
  void emitMute(bool muted) => _socket?.emit('mute', {'muted': muted});
  void emitVideoToggle(bool enabled) => _socket?.emit('videoToggle', {'enabled': enabled});
  void emitAudioLevel(num level) => _socket?.emit('audioLevel', {'level': level});
  void leaveRoom() => _socket?.emit('leaveRoom');

  void onRoomMode(FutureOr<void> Function(Map<String, dynamic>) handler) {
    _socket?.on('roomMode', (data) {
      handler(Map<String, dynamic>.from(data));
    });
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
  }
}
