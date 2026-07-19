import 'device.dart';

sealed class PairingState {
  const PairingState();
}

class PairingIdle extends PairingState {
  const PairingIdle();
}

class PairingDiscovering extends PairingState {
  const PairingDiscovering();
}

class PairingFoundDevice extends PairingState {
  const PairingFoundDevice(this.device);
  final Device device;
}

class PairingAwaitingAccept extends PairingState {
  const PairingAwaitingAccept(this.code);
  final String code;
}

class PairingConnected extends PairingState {
  const PairingConnected(this.device);
  final Device device;
}

class PairingFailed extends PairingState {
  const PairingFailed(this.message);
  final String message;
}
