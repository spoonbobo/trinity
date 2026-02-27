import 'package:flutter/material.dart';

/// Fallback panel that embeds the OpenClaw Canvas host via an iframe
/// for full HTML/CSS/JS content the agent has written to the Canvas directory.
///
/// This is used when the agent writes raw HTML to the canvas rather than
/// using A2UI structured components.
class CanvasWebView extends StatelessWidget {
  final String gatewayUrl;
  final String sessionId;

  const CanvasWebView({
    super.key,
    this.gatewayUrl = 'http://localhost:18789',
    this.sessionId = 'main',
  });

  String get canvasUrl => '$gatewayUrl/__openclaw__/canvas/$sessionId/';

  @override
  Widget build(BuildContext context) {
    // On Flutter Web, we use HtmlElementView to embed an iframe.
    // This requires dart:html which is web-only.
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        border: Border.all(color: const Color(0xFF2A2A2A)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF2A2A2A)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.web, size: 14, color: Color(0xFF6B6B6B)),
                const SizedBox(width: 8),
                Text(
                  'Canvas: $sessionId',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const Spacer(),
                Text(
                  canvasUrl,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF3A3A3A),
                        fontSize: 10,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Canvas iframe renders here on web.\n'
                'URL: $canvasUrl',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF4A4A4A),
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
