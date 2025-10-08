import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'env.dart';

final dioProvider = Provider<Dio>(() {
  return Dio(BaseOptions(baseUrl: Env.signalingBase, connectTimeout: const Duration(seconds: 5)));
});
