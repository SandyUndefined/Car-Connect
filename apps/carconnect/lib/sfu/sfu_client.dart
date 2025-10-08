import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;

typedef CB = void Function(dynamic);

class SfuClient {
  final String baseUrl;
  final String token;
  IO.Socket? _io;

  SfuClient(this.baseUrl, this.token);

  void connect() {
    _io = IO.io(baseUrl, {
      'transports': ['websocket'],
      'autoConnect': false,
      'auth': {'token': token},
      'forceNew': true
    });
    _io!.connect();
  }

  void on(String evt, CB cb) => _io?.on(evt, cb);

  void emitAck(String evt, dynamic data, void Function(dynamic) cb) {
    _io?.emitWithAck(evt, data, ack: cb);
  }

  void dispose() {
    _io?.dispose();
    _io = null;
  }
}
