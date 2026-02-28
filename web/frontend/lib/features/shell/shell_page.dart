import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/gateway_client.dart' as gw;
import '../../core/auth.dart';
import '../../models/ws_frame.dart';
import '../prompt_bar/prompt_bar.dart';
import '../chat/chat_stream.dart';
import '../canvas/a2ui_renderer.dart';
import '../governance/approval_panel.dart';

final _sharedDevice = DeviceIdentity.generate();
final _sharedAuth = GatewayAuth(
  token: const String.fromEnvironment(
    'GATEWAY_TOKEN',
    defaultValue: 'replace-me-with-a-real-token',
  ),
  device: _sharedDevice,
);
const _wsUrl = String.fromEnvironment(
  'GATEWAY_WS_URL',
  defaultValue: 'ws://localhost:18789',
);

final gatewayClientProvider = ChangeNotifierProvider<gw.GatewayClient>((ref) {
  return gw.GatewayClient(url: _wsUrl, auth: _sharedAuth);
});


class ShellPage extends ConsumerStatefulWidget {
  const ShellPage({super.key});

  @override
  ConsumerState<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends ConsumerState<ShellPage> {
  bool _showGovernance = false;
  StreamSubscription<WsEvent>? _approvalSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final client = ref.read(gatewayClientProvider);
      client.connect().catchError((e) {
        debugPrint('[Shell] connect failed: $e');
      });
      // Auto-show governance panel when approval events arrive
      _approvalSub = client.approvalEvents.listen((_) {
        if (!_showGovernance && mounted) {
          setState(() => _showGovernance = true);
        }
      });
    });
  }

  @override
  void dispose() {
    _approvalSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(gatewayClientProvider);
    final isConnected = client.state == gw.ConnectionState.connected;

    return Scaffold(
      body: Column(
        children: [
          _buildStatusBar(client.state),
          Expanded(
            child: Row(
              children: [
                // Main chat area
                Expanded(
                  flex: 6,
                  child: const ChatStreamView(),
                ),
                // Canvas panel (always visible)
                Expanded(
                  flex: 4,
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: Color(0xFF2A2A2A)),
                      ),
                    ),
                    child: const A2UIRendererPanel(),
                  ),
                ),
                // Governance panel (auto-shows on approval events)
                if (_showGovernance)
                  Expanded(
                    flex: 4,
                    child: Container(
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(color: Color(0xFF2A2A2A)),
                        ),
                      ),
                      child: ApprovalPanel(
                        onAllResolved: () {
                          if (mounted) setState(() => _showGovernance = false);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          PromptBar(enabled: isConnected),
        ],
      ),
    );
  }

  Widget _buildStatusBar(gw.ConnectionState state) {
    Color dotColor;
    String label;
    switch (state) {
      case gw.ConnectionState.connected:
        dotColor = const Color(0xFF6EE7B7);
        label = 'CONNECTED';
        break;
      case gw.ConnectionState.connecting:
        dotColor = const Color(0xFFFBBF24);
        label = 'CONNECTING...';
        break;
      case gw.ConnectionState.error:
        dotColor = const Color(0xFFEF4444);
        label = 'ERROR';
        break;
      case gw.ConnectionState.disconnected:
        dotColor = const Color(0xFF6B6B6B);
        label = 'DISCONNECTED';
        break;
    }

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const Spacer(),
          Text(
            'TRINITY AGI',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 2,
                  color: const Color(0xFF3A3A3A),
                ),
          ),
        ],
      ),
    );
  }
}
