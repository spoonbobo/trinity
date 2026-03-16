import 'dart:convert';

/// A single entry in the chat stream.
/// Pure Dart -- no Flutter or dart:html dependency.
class ChatEntry {
  final String role; // 'user', 'assistant', 'tool', 'system'
  final String content;
  final String? toolName;
  final String? toolCallId; // e.g. 'functions.read:0' -- used to match results to calls
  final bool isStreaming;
  final DateTime timestamp;
  final List<Map<String, dynamic>>? attachments;
  final Map<String, dynamic>? metadata; // Parsed tool args (command, path, etc.)
  final DateTime? startedAt; // When tool call started (for duration tracking)
  final Duration? elapsed; // How long the tool call took

  ChatEntry({
    required this.role,
    required this.content,
    this.toolName,
    this.toolCallId,
    this.isStreaming = false,
    this.attachments,
    this.metadata,
    this.startedAt,
    this.elapsed,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  ChatEntry copyWith({
    String? content,
    bool? isStreaming,
    Duration? elapsed,
  }) =>
      ChatEntry(
        role: role,
        content: content ?? this.content,
        toolName: toolName,
        toolCallId: toolCallId,
        isStreaming: isStreaming ?? this.isStreaming,
        attachments: attachments,
        metadata: metadata,
        startedAt: startedAt,
        elapsed: elapsed ?? this.elapsed,
        timestamp: timestamp,
      );

  /// Try to parse a stringified args blob into structured metadata.
  /// Returns null if content is empty or not valid JSON.
  static Map<String, dynamic>? parseToolMetadata(String? toolName, String args) {
    if (args.isEmpty) return null;
    try {
      final parsed = json.decode(args);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {
      // Not JSON -- try to extract key info from plain text
    }
    return null;
  }

  /// Parse tool args from either a JSON string or structured object.
  static Map<String, dynamic>? parseToolMetadataDynamic(
      String? toolName, dynamic args) {
    if (args == null) return null;
    if (args is Map<String, dynamic>) return args;
    if (args is Map) {
      return args.map((k, v) => MapEntry('$k', v));
    }
    if (args is String) {
      return parseToolMetadata(toolName, args);
    }
    return null;
  }

  /// Human-readable summary of tool metadata for display.
  String? get metadataSummary {
    final m = metadata;
    if (m == null) return null;
    final name = toolName ?? '';

    if (name == 'exec' || name == 'bash' || name == 'Bash') {
      final cmd = m['command'] as String? ?? m['cmd'] as String? ?? '';
      if (cmd.isNotEmpty) return cmd;
    }

    if (name == 'read' ||
        name == 'Read' ||
        name == 'write' ||
        name == 'Write' ||
        name == 'edit' ||
        name == 'Edit') {
      final path = m['filePath'] as String? ??
          m['path'] as String? ??
          m['file'] as String? ??
          '';
      if (path.isNotEmpty) return path;
    }

    if (name == 'glob' || name == 'Glob') {
      final pattern = m['pattern'] as String? ?? '';
      if (pattern.isNotEmpty) return pattern;
    }

    if (name == 'grep' || name == 'Grep') {
      final pattern = m['pattern'] as String? ?? '';
      final include = m['include'] as String? ?? '';
      if (pattern.isNotEmpty) {
        return include.isNotEmpty ? '$pattern ($include)' : pattern;
      }
    }

    if (name == 'canvas_ui') return 'rendering surface';

    final cmd = m['command'] as String? ??
        m['description'] as String? ??
        m['query'] as String? ??
        m['prompt'] as String? ??
        '';
    if (cmd.isNotEmpty) return cmd;

    return null;
  }

  /// Secondary metadata line (workdir, host, path context).
  String? get metadataDetail {
    final m = metadata;
    if (m == null) return null;
    final parts = <String>[];
    final name = toolName ?? '';

    if (name == 'exec' || name == 'bash' || name == 'Bash') {
      final workdir = m['workdir'] as String? ?? m['cwd'] as String? ?? '';
      if (workdir.isNotEmpty) parts.add(workdir);
      final host = m['host'] as String? ?? '';
      if (host.isNotEmpty && host != 'sandbox') parts.add('host:$host');
    }

    if (name == 'read' || name == 'Read') {
      final offset = m['offset'];
      final limit = m['limit'];
      if (offset != null || limit != null) {
        parts.add(
            'lines ${offset ?? 1}-${((offset as int?) ?? 1) + ((limit as int?) ?? 2000)}');
      }
    }

    if (name == 'grep' || name == 'Grep') {
      final path = m['path'] as String? ?? '';
      if (path.isNotEmpty) parts.add(path);
    }

    return parts.isEmpty ? null : parts.join('  ');
  }
}
