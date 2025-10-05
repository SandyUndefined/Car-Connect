import 'package:flutter_riverpod/flutter_riverpod.dart';

final sfuControllerProvider =
    NotifierProvider<SfuController, SfuState>(SfuController.new);

class SfuState {
  final bool connecting;
  final bool connected;

  const SfuState({this.connecting = false, this.connected = false});

  SfuState copyWith({bool? connecting, bool? connected}) => SfuState(
        connecting: connecting ?? this.connecting,
        connected: connected ?? this.connected,
      );
}

class SfuController extends Notifier<SfuState> {
  @override
  SfuState build() => const SfuState();

  Future<void> start(String token) async {
    state = state.copyWith(connecting: true);
    // TODO: Implement SFU start logic using [token].
    state = state.copyWith(connecting: false, connected: true);
  }
}
