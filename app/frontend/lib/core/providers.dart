import 'dart:html' as html;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'gateway_client.dart' as gw;
import 'auth.dart';
import 'terminal_client.dart';
import 'auth_client.dart' show AuthClient, AuthRole, OpenClawInfo, OpenClawStatus, roleToString;

String _resolveAuthBaseUrl() {
  const configured = String.fromEnvironment('AUTH_SERVICE_URL', defaultValue: '');
  if (configured.isNotEmpty) return configured;
  return html.window.location.origin;
}

String _resolveGatewayWsUrl() {
  const configured = String.fromEnvironment('GATEWAY_WS_URL', defaultValue: '');
  if (configured.isNotEmpty) return configured;
  final location = html.window.location;
  final scheme = location.protocol == 'https:' ? 'wss' : 'ws';
  return '$scheme://${location.host}/ws';
}

String _resolveTerminalWsUrl() {
  const configured = String.fromEnvironment('TERMINAL_WS_URL', defaultValue: '');
  if (configured.isNotEmpty) return configured;
  final location = html.window.location;
  final scheme = location.protocol == 'https:' ? 'wss' : 'ws';
  return '$scheme://${location.host}/terminal/';
}

final _authBaseUrl = _resolveAuthBaseUrl();

final authClientProvider = ChangeNotifierProvider<AuthClient>((ref) {
  return AuthClient(authServiceBaseUrl: _authBaseUrl);
});

final _sharedDevice = DeviceIdentity.generate();

/// Shared [GatewayAuth] that uses the JWT from the current auth session.
/// The token is updated by [_syncAuthToken] whenever the auth state changes.
final _sharedAuth = GatewayAuth(token: '', device: _sharedDevice);

final _gatewayWsUrl = _resolveGatewayWsUrl();
final _terminalWsUrl = _resolveTerminalWsUrl();

/// Keep [_sharedAuth] in sync with the current JWT from [AuthClient].
void _syncAuthToken(AuthClient authClient) {
  final jwt = authClient.state.token ?? '';
  if (_sharedAuth.token != jwt) {
    _sharedAuth.updateToken(jwt);
  }
}

final gatewayClientProvider = ChangeNotifierProvider<gw.GatewayClient>((ref) {
  final authClient = ref.read(authClientProvider);
  _syncAuthToken(authClient);
  final client = gw.GatewayClient(url: _gatewayWsUrl, auth: _sharedAuth);
  client.setOpenClawId(authClient.state.activeOpenClawId);
  // Listen for future auth state changes and push new JWT to gateway auth.
  authClient.addListener(() => _syncAuthToken(authClient));
  return client;
});

final terminalClientProvider = ChangeNotifierProvider<TerminalProxyClient>((ref) {
  final authClient = ref.read(authClientProvider);
  _syncAuthToken(authClient);
  final role = roleToString(authClient.state.role);
  final client = TerminalProxyClient(url: _terminalWsUrl, auth: _sharedAuth, role: role);
  client.setOpenClawId(authClient.state.activeOpenClawId);
  return client;
});

/// Create an independent TerminalProxyClient for scoped use (e.g. per-channel
/// onboarding terminal). Caller is responsible for calling dispose() when done.
TerminalProxyClient createScopedTerminalClient(WidgetRef ref) {
  final authClient = ref.read(authClientProvider);
  _syncAuthToken(authClient);
  final role = roleToString(authClient.state.role);
  final client = TerminalProxyClient(url: _terminalWsUrl, auth: _sharedAuth, role: role);
  client.setOpenClawId(authClient.state.activeOpenClawId);
  return client;
}

/// Active session key — defaults to 'main'.
final activeSessionProvider = StateProvider<String>((ref) => 'main');

/// The currently selected OpenClaw instance ID.
final activeOpenClawProvider = StateProvider<String?>((ref) => null);
