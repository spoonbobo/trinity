import 'package:flutter_test/flutter_test.dart';
import 'package:trinity_shell/features/chat/chat_stream_processor.dart';
import 'package:trinity_shell/models/ws_frame.dart';

import 'fixtures/simple_greeting.dart' as simpleGreeting;
import 'fixtures/text_then_tools.dart' as textThenTools;
import 'fixtures/tools_only.dart' as toolsOnly;
import 'fixtures/parallel_tools.dart' as parallelTools;

void main() {
  // -----------------------------------------------------------------------
  // Streaming path tests (processEvent)
  // -----------------------------------------------------------------------
  group('Streaming path (processEvent)', () {
    test('simple greeting: lifecycle -> deltas -> final -> lifecycle end', () {
      final p = ChatStreamProcessor();
      for (final e in simpleGreeting.streamingEvents) {
        p.processEvent(e);
      }
      expect(p.entries.length, 2);
      expect(p.entries[0].role, 'user');
      expect(p.entries[1].role, 'assistant');
      expect(p.entries[1].isStreaming, false);
      expect(p.entries[1].content,
          simpleGreeting.expectedEntries[1]['content']);
    });

    test('text-then-tools: correct order [user, asst, tool, tool, tool, asst]',
        () {
      final p = ChatStreamProcessor();
      for (final e in textThenTools.streamingEvents) {
        p.processEvent(e);
      }
      final roles = p.entries.map((e) => e.role).toList();
      expect(roles,
          ['user', 'assistant', 'tool', 'tool', 'tool', 'assistant']);
      // Pre-tool text
      expect(p.entries[1].content,
          textThenTools.expectedEntries[1]['content']);
      // Post-tool text (should be AFTER tool cards, at index 5)
      expect(p.entries[5].content,
          textThenTools.expectedEntries[5]['content']);
    });

    test('text-then-tools: no duplicate tool entries', () {
      final p = ChatStreamProcessor();
      for (final e in textThenTools.streamingEvents) {
        p.processEvent(e);
      }
      final toolEntries = p.entries.where((e) => e.role == 'tool').toList();
      final ids = toolEntries.map((e) => e.toolCallId).toSet();
      expect(ids.length, toolEntries.length,
          reason: 'no duplicate toolCallIds');
    });

    test('tools-only: no empty assistant entry', () {
      final p = ChatStreamProcessor();
      for (final e in toolsOnly.streamingEvents) {
        p.processEvent(e);
      }
      final emptyAssistants = p.entries
          .where((e) => e.role == 'assistant' && e.content.trim().isEmpty);
      expect(emptyAssistants, isEmpty);
    });

    test('tools-only: correct order [user, tool, tool, assistant]', () {
      final p = ChatStreamProcessor();
      for (final e in toolsOnly.streamingEvents) {
        p.processEvent(e);
      }
      final roles = p.entries.map((e) => e.role).toList();
      expect(roles, ['user', 'tool', 'tool', 'assistant']);
    });

    test('parallel-tools: out-of-order results matched to correct entries',
        () {
      final p = ChatStreamProcessor();
      for (final e in parallelTools.streamingEvents) {
        p.processEvent(e);
      }
      final toolEntries = p.entries.where((e) => e.role == 'tool').toList();
      expect(toolEntries.length, 3);
      for (final te in toolEntries) {
        expect(te.isStreaming, false,
            reason: '${te.toolCallId} should be completed');
        expect(te.content, isNotEmpty,
            reason: '${te.toolCallId} should have result');
      }
      // Verify results match the right toolCallIds
      final tool0 =
          toolEntries.firstWhere((e) => e.toolCallId == 'functions.read:0');
      expect(tool0.content, contains('SOUL.md'));
      final tool1 =
          toolEntries.firstWhere((e) => e.toolCallId == 'functions.read:1');
      expect(tool1.content, contains('USER.md'));
      final tool2 =
          toolEntries.firstWhere((e) => e.toolCallId == 'functions.read:2');
      expect(tool2.content, contains('MEMORY.md'));
    });

    test('duplicate tool_call events are deduplicated', () {
      final p = ChatStreamProcessor();
      // Lifecycle start
      p.processEvent(WsEvent.fromJson({
        'event': 'agent',
        'payload': {
          'stream': 'lifecycle',
          'data': {'phase': 'start'},
        },
      }));
      // Same tool call sent twice (once as 'tool_call', once as 'tool')
      p.processEvent(WsEvent.fromJson({
        'event': 'agent',
        'payload': {
          'stream': 'tool_call',
          'data': {
            'phase': 'start',
            'tool': 'exec',
            'id': 'functions.exec:0',
            'toolCallId': 'functions.exec:0',
            'args': {'command': 'ls'},
          },
        },
      }));
      p.processEvent(WsEvent.fromJson({
        'event': 'agent',
        'payload': {
          'stream': 'tool',
          'data': {
            'phase': 'start',
            'tool': 'exec',
            'id': 'functions.exec:0',
            'toolCallId': 'functions.exec:0',
            'args': {'command': 'ls'},
          },
        },
      }));
      final toolEntries = p.entries.where((e) => e.role == 'tool').toList();
      expect(toolEntries.length, 1,
          reason: 'should deduplicate by toolCallId');
    });
  });

  // -----------------------------------------------------------------------
  // History path tests (loadHistory)
  // -----------------------------------------------------------------------
  group('History path (loadHistory)', () {
    test('simple greeting: produces [user, assistant]', () {
      final p = ChatStreamProcessor();
      p.loadHistory(simpleGreeting.historyMessages);
      expect(p.entries.length, 2);
      expect(p.entries.map((e) => e.role).toList(), ['user', 'assistant']);
      expect(p.entries[1].content,
          simpleGreeting.expectedEntries[1]['content']);
    });

    test('text-then-tools: correct order with clean pre-tool text', () {
      final p = ChatStreamProcessor();
      p.loadHistory(textThenTools.historyMessages);
      final roles = p.entries.map((e) => e.role).toList();
      expect(roles,
          ['user', 'assistant', 'tool', 'tool', 'tool', 'assistant']);
      // Pre-tool text should be clean (no whitespace spacers)
      final preToolText = p.entries[1].content;
      expect(preToolText.trim(), preToolText,
          reason: 'no trailing whitespace');
      expect(preToolText, isNot(contains('\n \n')),
          reason: 'no spacer artifacts');
    });

    test('tools-only: no empty assistant entry', () {
      final p = ChatStreamProcessor();
      p.loadHistory(toolsOnly.historyMessages);
      final emptyAssistants = p.entries
          .where((e) => e.role == 'assistant' && e.content.trim().isEmpty);
      expect(emptyAssistants, isEmpty);
    });

    test('tools-only: correct order [user, tool, tool, assistant]', () {
      final p = ChatStreamProcessor();
      p.loadHistory(toolsOnly.historyMessages);
      final roles = p.entries.map((e) => e.role).toList();
      expect(roles, ['user', 'tool', 'tool', 'assistant']);
    });

    test('parallel-tools: tool results matched to correct entries', () {
      final p = ChatStreamProcessor();
      p.loadHistory(parallelTools.historyMessages);
      final toolEntries = p.entries.where((e) => e.role == 'tool').toList();
      expect(toolEntries.length, 3);
      expect(toolEntries[0].toolCallId, 'functions.read:0');
      expect(toolEntries[1].toolCallId, 'functions.read:1');
      expect(toolEntries[2].toolCallId, 'functions.read:2');
    });
  });

  // -----------------------------------------------------------------------
  // Parity tests (streaming == history)
  // -----------------------------------------------------------------------
  group('Parity (streaming == history)', () {
    final fixtures = {
      'simple_greeting': (
        streaming: simpleGreeting.streamingEvents,
        history: simpleGreeting.historyMessages,
        expected: simpleGreeting.expectedEntries,
      ),
      'text_then_tools': (
        streaming: textThenTools.streamingEvents,
        history: textThenTools.historyMessages,
        expected: textThenTools.expectedEntries,
      ),
      'tools_only': (
        streaming: toolsOnly.streamingEvents,
        history: toolsOnly.historyMessages,
        expected: toolsOnly.expectedEntries,
      ),
      'parallel_tools': (
        streaming: parallelTools.streamingEvents,
        history: parallelTools.historyMessages,
        expected: parallelTools.expectedEntries,
      ),
    };

    for (final entry in fixtures.entries) {
      test('${entry.key}: streaming and history produce same role sequence',
          () {
        final sp = ChatStreamProcessor();
        for (final e in entry.value.streaming) {
          sp.processEvent(e);
        }

        final hp = ChatStreamProcessor();
        hp.loadHistory(entry.value.history);

        expect(sp.entries.length, hp.entries.length,
            reason: 'same number of entries');

        final streamingRoles = sp.entries.map((e) => e.role).toList();
        final historyRoles = hp.entries.map((e) => e.role).toList();
        expect(streamingRoles, historyRoles,
            reason: 'same role sequence');
      });

      test('${entry.key}: streaming and history produce same content', () {
        final sp = ChatStreamProcessor();
        for (final e in entry.value.streaming) {
          sp.processEvent(e);
        }

        final hp = ChatStreamProcessor();
        hp.loadHistory(entry.value.history);

        for (int i = 0; i < sp.entries.length; i++) {
          expect(sp.entries[i].role, hp.entries[i].role,
              reason: 'entry $i role matches');
          if (sp.entries[i].role == 'assistant' ||
              sp.entries[i].role == 'user') {
            expect(sp.entries[i].content.trim(), hp.entries[i].content.trim(),
                reason: 'entry $i content matches');
          }
          expect(sp.entries[i].toolName, hp.entries[i].toolName,
              reason: 'entry $i toolName matches');
        }
      });
    }
  });

  // -----------------------------------------------------------------------
  // Expected output tests (ground truth)
  // -----------------------------------------------------------------------
  group('Expected output (ground truth)', () {
    final fixtures = {
      'simple_greeting': (
        streaming: simpleGreeting.streamingEvents,
        history: simpleGreeting.historyMessages,
        expected: simpleGreeting.expectedEntries,
      ),
      'text_then_tools': (
        streaming: textThenTools.streamingEvents,
        history: textThenTools.historyMessages,
        expected: textThenTools.expectedEntries,
      ),
      'tools_only': (
        streaming: toolsOnly.streamingEvents,
        history: toolsOnly.historyMessages,
        expected: toolsOnly.expectedEntries,
      ),
      'parallel_tools': (
        streaming: parallelTools.streamingEvents,
        history: parallelTools.historyMessages,
        expected: parallelTools.expectedEntries,
      ),
    };

    for (final entry in fixtures.entries) {
      test('${entry.key}: streaming matches expected entries', () {
        final p = ChatStreamProcessor();
        for (final e in entry.value.streaming) {
          p.processEvent(e);
        }
        expect(p.entries.length, entry.value.expected.length,
            reason: 'correct number of entries');
        for (int i = 0; i < p.entries.length; i++) {
          expect(p.entries[i].role, entry.value.expected[i]['role'],
              reason: 'entry $i role');
          if (entry.value.expected[i].containsKey('content')) {
            expect(
                p.entries[i].content, entry.value.expected[i]['content'],
                reason: 'entry $i content');
          }
          if (entry.value.expected[i].containsKey('toolName')) {
            expect(
                p.entries[i].toolName, entry.value.expected[i]['toolName'],
                reason: 'entry $i toolName');
          }
          if (entry.value.expected[i].containsKey('toolCallId')) {
            expect(p.entries[i].toolCallId,
                entry.value.expected[i]['toolCallId'],
                reason: 'entry $i toolCallId');
          }
        }
      });

      test('${entry.key}: history matches expected entry count and roles',
          () {
        final p = ChatStreamProcessor();
        p.loadHistory(entry.value.history);
        expect(p.entries.length, entry.value.expected.length,
            reason: 'correct number of entries');
        for (int i = 0; i < p.entries.length; i++) {
          expect(p.entries[i].role, entry.value.expected[i]['role'],
              reason: 'entry $i role');
        }
      });
    }
  });

  // -----------------------------------------------------------------------
  // Static utility tests
  // -----------------------------------------------------------------------
  group('Static utilities', () {
    test('extractContent handles string', () {
      expect(ChatStreamProcessor.extractContent('hello'), 'hello');
    });

    test('extractContent handles list of text blocks', () {
      final result = ChatStreamProcessor.extractContent([
        {'type': 'text', 'text': 'hello'},
        {'type': 'text', 'text': 'world'},
      ]);
      expect(result, 'hello\nworld');
    });

    test('extractContent skips thinking blocks', () {
      final result = ChatStreamProcessor.extractContent([
        {'type': 'thinking', 'text': 'internal thought'},
        {'type': 'text', 'text': 'visible text'},
      ]);
      expect(result, 'visible text');
    });

    test('extractA2UIText extracts payload after marker', () {
      final result = ChatStreamProcessor.extractA2UIText(
          'some text __A2UI__\n{"surfaceUpdate":{}}');
      expect(result, isNotNull);
      expect(result, contains('__A2UI__'));
    });

    test('extractA2UIText returns null without marker', () {
      expect(
          ChatStreamProcessor.extractA2UIText('no marker here'), isNull);
    });

    test('clear resets all state', () {
      final p = ChatStreamProcessor();
      p.processEvent(WsEvent.fromJson({
        'event': 'agent',
        'payload': {
          'stream': 'lifecycle',
          'data': {'phase': 'start'},
        },
      }));
      expect(p.agentThinking, true);
      p.clear();
      expect(p.entries, isEmpty);
      expect(p.agentThinking, false);
    });
  });
}
