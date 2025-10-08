import 'package:dio/dio.dart';

class SignalingClient {
  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
  final String base;

  SignalingClient(this.base);

  Future<Map<String, dynamic>> createRoom(String hostId, {String mode = 'mesh'}) async {
    final res = await _dio.post('$base/v1/rooms', data: {'hostId': hostId, 'mode': mode});
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> joinRoom(String roomId) async {
    final res = await _dio.post('$base/v1/rooms/$roomId/join');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> turnCred() async {
    final res = await _dio.post('$base/turn-cred');
    return Map<String, dynamic>.from(res.data as Map);
  }
}
