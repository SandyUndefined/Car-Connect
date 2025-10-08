import 'package:dio/dio.dart';

class SignalingRest {
  final Dio dio;
  SignalingRest(this.dio);

  Future<(String roomId, String token)> createRoom(String hostId, {String mode = "mesh"}) async {
    final r = await dio.post('/v1/rooms', data: {"hostId": hostId, "mode": mode});
    return (r.data['room']['id'] as String, r.data['token'] as String);
  }

  Future<String> joinRoom(String roomId, String userId) async {
    final r = await dio.post('/v1/rooms/$roomId/join', data: {"userId": userId});
    return r.data['token'] as String;
  }

  Future<List<Map<String, dynamic>>> getTurnIceServers(String userId) async {
    final r = await dio.post('/turn-cred', data: {"userId": userId});
    final List list = r.data['iceServers'];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
