import 'package:uuid/uuid.dart';

class DeviceIdentity {
  final String id;

  DeviceIdentity._(this.id);

  /// Generates a stable device ID per browser session.
  /// In production, persist this in localStorage.
  factory DeviceIdentity.generate() {
    return DeviceIdentity._(const Uuid().v4());
  }
}

class GatewayAuth {
  final String token;
  final DeviceIdentity device;

  const GatewayAuth({required this.token, required this.device});

  Map<String, dynamic> toConnectParams() => {
        'auth': {'token': token},
        'device': {'id': device.id},
      };
}
