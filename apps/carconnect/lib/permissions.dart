import 'package:permission_handler/permission_handler.dart';

Future<bool> ensureAvPermissions() async {
  final statuses = await [Permission.camera, Permission.microphone].request();
  return statuses.values.every((s) => s.isGranted);
}
