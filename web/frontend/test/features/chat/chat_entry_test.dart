import 'package:flutter_test/flutter_test.dart';
import 'package:trinity_shell/features/chat/chat_stream.dart';

void main() {
  group('ChatEntry', () {
    test('creates with required fields', () {
      final entry = ChatEntry(role: 'user', content: 'hello');
      expect(entry.role, 'user');
      expect(entry.content, 'hello');
      expect(entry.toolName, isNull);
      expect(entry.isStreaming, false);
      expect(entry.attachments, isNull);
      expect(entry.metadata, isNull);
      expect(entry.startedAt, isNull);
      expect(entry.elapsed, isNull);
      expect(entry.timestamp, isNotNull);
    });

    test('creates with all fields', () {
      final ts = DateTime(2026, 1, 1);
      final attachments = [
        {'name': 'photo.jpg', 'mimeType': 'image/jpeg', 'base64': 'abc'}
      ];
      final meta = {'command': 'ls -la', 'workdir': '/tmp'};
      final entry = ChatEntry(
        role: 'assistant',
        content: 'response',
        toolName: 'exec',
        isStreaming: true,
        attachments: attachments,
        metadata: meta,
        startedAt: ts,
        timestamp: ts,
      );
      expect(entry.role, 'assistant');
      expect(entry.toolName, 'exec');
      expect(entry.isStreaming, true);
      expect(entry.attachments!.length, 1);
      expect(entry.metadata, meta);
      expect(entry.startedAt, ts);
      expect(entry.timestamp, ts);
    });

    test('copyWith preserves non-overridden fields', () {
      final original = ChatEntry(
        role: 'tool',
        content: 'running...',
        toolName: 'exec',
        isStreaming: true,
        attachments: [{'name': 'test.txt'}],
        metadata: {'command': 'echo hi'},
        startedAt: DateTime(2026, 1, 1),
      );
      final updated = original.copyWith(
        content: 'Done',
        isStreaming: false,
        elapsed: const Duration(seconds: 2),
      );
      expect(updated.role, 'tool');
      expect(updated.content, 'Done');
      expect(updated.isStreaming, false);
      expect(updated.toolName, 'exec');
      expect(updated.attachments!.length, 1);
      expect(updated.metadata, {'command': 'echo hi'});
      expect(updated.startedAt, DateTime(2026, 1, 1));
      expect(updated.elapsed, const Duration(seconds: 2));
    });

    test('copyWith with no overrides returns equivalent entry', () {
      final original = ChatEntry(role: 'system', content: 'info');
      final copy = original.copyWith();
      expect(copy.role, original.role);
      expect(copy.content, original.content);
      expect(copy.isStreaming, original.isStreaming);
    });
  });

  group('ChatEntry.parseToolMetadata', () {
    test('parses valid JSON args', () {
      final meta = ChatEntry.parseToolMetadata('exec', '{"command":"ls -la","workdir":"/tmp"}');
      expect(meta, isNotNull);
      expect(meta!['command'], 'ls -la');
      expect(meta['workdir'], '/tmp');
    });

    test('returns null for empty args', () {
      expect(ChatEntry.parseToolMetadata('exec', ''), isNull);
    });

    test('returns null for non-JSON args', () {
      expect(ChatEntry.parseToolMetadata('exec', 'just plain text'), isNull);
    });

    test('returns null for JSON array (not map)', () {
      expect(ChatEntry.parseToolMetadata('exec', '[1,2,3]'), isNull);
    });
  });

  group('ChatEntry metadata getters', () {
    test('metadataSummary for exec returns command', () {
      final entry = ChatEntry(
        role: 'tool',
        content: '',
        toolName: 'exec',
        metadata: {'command': 'docker ps', 'workdir': '/app'},
      );
      expect(entry.metadataSummary, 'docker ps');
    });

    test('metadataSummary for read returns filePath', () {
      final entry = ChatEntry(
        role: 'tool',
        content: '',
        toolName: 'read',
        metadata: {'filePath': '/src/main.dart'},
      );
      expect(entry.metadataSummary, '/src/main.dart');
    });

    test('metadataSummary for glob returns pattern', () {
      final entry = ChatEntry(
        role: 'tool',
        content: '',
        toolName: 'glob',
        metadata: {'pattern': '**/*.dart'},
      );
      expect(entry.metadataSummary, '**/*.dart');
    });

    test('metadataSummary for grep returns pattern with include', () {
      final entry = ChatEntry(
        role: 'tool',
        content: '',
        toolName: 'grep',
        metadata: {'pattern': 'TODO', 'include': '*.dart', 'path': '/src'},
      );
      expect(entry.metadataSummary, 'TODO (*.dart)');
    });

    test('metadataDetail for exec returns workdir and host', () {
      final entry = ChatEntry(
        role: 'tool',
        content: '',
        toolName: 'exec',
        metadata: {'command': 'ls', 'workdir': '/app', 'host': 'gateway'},
      );
      expect(entry.metadataDetail, '/app  host:gateway');
    });

    test('metadataDetail for exec omits default sandbox host', () {
      final entry = ChatEntry(
        role: 'tool',
        content: '',
        toolName: 'exec',
        metadata: {'command': 'ls', 'host': 'sandbox'},
      );
      expect(entry.metadataDetail, isNull);
    });

    test('metadataDetail for read returns line range', () {
      final entry = ChatEntry(
        role: 'tool',
        content: '',
        toolName: 'read',
        metadata: {'filePath': '/file.dart', 'offset': 10, 'limit': 50},
      );
      expect(entry.metadataDetail, 'lines 10-60');
    });

    test('metadataSummary returns null when no metadata', () {
      final entry = ChatEntry(role: 'tool', content: 'raw text');
      expect(entry.metadataSummary, isNull);
      expect(entry.metadataDetail, isNull);
    });
  });
}
