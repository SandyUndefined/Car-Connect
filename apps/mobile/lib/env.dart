class Env {
  static const signalingBase =
      String.fromEnvironment('SIGNALING_BASE', defaultValue: 'http://localhost:8080');
}
