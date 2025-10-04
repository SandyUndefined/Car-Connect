class Env {
  // Replace with your LAN IP when testing on device
  static const signalingBase = String.fromEnvironment(
    'SIGNALING_BASE',
    defaultValue: 'http://localhost:8080',
  );
}
