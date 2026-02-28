import 'package:uuid/uuid.dart';

class DeviceIdentity {
  final String id;

  DeviceIdentity._(this.id);

  factory DeviceIdentity.generate() {
    return DeviceIdentity._(const Uuid().v4());
  }
}

class GatewayAuth {
  final String token;
  final DeviceIdentity device;

  const GatewayAuth({required this.token, required this.device});

  Map<String, dynamic> toConnectParams(String? nonce) => {
        'auth': {'token': token},
        'device': {
          'id': device.id,
          'publicKey': device.id,
          'signature': 'nosig',
          'signedAt': DateTime.now().millisecondsSinceEpoch,
          'nonce': nonce ?? '',
        },
      };
}
