import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:force_graph/force_graph.dart';

import '../../core/theme.dart';
import '../../main.dart' show authClientProvider;

class KnowledgeDialog extends ConsumerStatefulWidget {
  const KnowledgeDialog({super.key});

  @override
  ConsumerState<KnowledgeDialog> createState() => _KnowledgeDialogState();
}

class _KnowledgeDialogState extends ConsumerState<KnowledgeDialog> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _graph;
  List<dynamic> _labels = const [];

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  String? _selectedLabel;
  String _searchQuery = '';
  String _entityKindFilter = 'all';
  String _activeView = 'graph';
  int _maxDepth = 3;
  int _maxNodes = 500;
  bool _neighborsOnly = false;
  bool _searchingRemote = false;
  bool _showAdvanced = false;
  bool _docsLoading = false;
  String? _docsError;
  List<Map<String, dynamic>> _documents = const [];
  bool _uploading = false;
  String _docStatusFilter = 'all';
  String _docTypeFilter = 'all';
  final TextEditingController _docSearchCtrl = TextEditingController();
  String _docQuery = '';

  String? _selectedNodeId;
  List<Map<String, dynamic>> _searchResults = const [];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      _searchQuery = _searchCtrl.text.trim();
      _refreshLocalSearch();
      _debouncedRemoteSearch();
    });
    _docSearchCtrl.addListener(() {
      setState(() => _docQuery = _docSearchCtrl.text.trim());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _docSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _loadWithParams(label: _selectedLabel);
  }

  Future<void> _loadDocuments() async {
    final auth = ref.read(authClientProvider);
    final token = auth.state.token;
    final openclawId = auth.state.activeOpenClawId;
    if (token == null || token.isEmpty || openclawId == null || openclawId.isEmpty) {
      setState(() {
        _docsLoading = false;
        _docsError = 'no active claw selected';
      });
      return;
    }

    setState(() {
      _docsLoading = true;
      _docsError = null;
    });

    try {
      final query = <String, String>{
        'limit': '200',
        if (_docStatusFilter != 'all') 'status': _docStatusFilter,
        if (_docTypeFilter != 'all') 'type': _docTypeFilter,
        if (_docQuery.trim().isNotEmpty) 'q': _docQuery.trim(),
      };
      final qs = query.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');

      final url =
          '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/lightrag-documents${qs.isEmpty ? '' : '?$qs'}';
      final request = html.HttpRequest();
      request.open('GET', url);
      request.setRequestHeader('Authorization', 'Bearer $token');
      final response = await _sendRequest(request);
      final decoded = Map<String, dynamic>.from(jsonDecode(response) as Map);
      final documents = (decoded['documents'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();

      if (!mounted) return;
      setState(() => _documents = documents);
    } catch (e) {
      if (!mounted) return;
      setState(() => _docsError = '$e');
    } finally {
      if (mounted) setState(() => _docsLoading = false);
    }
  }

  Future<void> _uploadDocument() async {
    final auth = ref.read(authClientProvider);
    final token = auth.state.token;
    final openclawId = auth.state.activeOpenClawId;
    if (token == null || token.isEmpty || openclawId == null || openclawId.isEmpty) return;

    final picker = html.FileUploadInputElement()..accept = '.pdf,.docx,.txt,.md';
    picker.click();
    await picker.onChange.first;
    final file = picker.files?.isNotEmpty == true ? picker.files!.first : null;
    if (file == null) return;

    setState(() {
      _uploading = true;
      _docsError = null;
    });

    try {
      final form = html.FormData();
      form.appendBlob('file', file, file.name);
      form.append('document_type', 'other');

      final url = '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/lightrag-documents';
      final request = html.HttpRequest();
      request.open('POST', url);
      request.setRequestHeader('Authorization', 'Bearer $token');
      final createRaw = await _sendRequestWithBody(request, form);
      final created = Map<String, dynamic>.from(jsonDecode(createRaw) as Map);
      final documentId = (created['document_id'] ?? '').toString();
      if (documentId.isNotEmpty) {
        await _ingestDocument(documentId, silent: true);
      }
      await _loadDocuments();
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _docsError = '$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _ingestDocument(String documentId, {bool silent = false}) async {
    final auth = ref.read(authClientProvider);
    final token = auth.state.token;
    final openclawId = auth.state.activeOpenClawId;
    if (token == null || token.isEmpty || openclawId == null || openclawId.isEmpty) return;

    try {
      final url =
          '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/lightrag-documents/${Uri.encodeQueryComponent(documentId)}/ingest';
      final request = html.HttpRequest();
      request.open('POST', url);
      request.setRequestHeader('Authorization', 'Bearer $token');
      await _sendRequest(request);
      if (!silent) {
        await _loadDocuments();
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _docsError = '$e');
    }
  }

  Future<void> _deleteDocument(String documentId) async {
    final confirmed = html.window.confirm('Delete this document from knowledge base?');
    if (!confirmed) return;

    final auth = ref.read(authClientProvider);
    final token = auth.state.token;
    final openclawId = auth.state.activeOpenClawId;
    if (token == null || token.isEmpty || openclawId == null || openclawId.isEmpty) return;

    try {
      final url =
          '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/lightrag-documents/${Uri.encodeQueryComponent(documentId)}';
      final request = html.HttpRequest();
      request.open('DELETE', url);
      request.setRequestHeader('Authorization', 'Bearer $token');
      await _sendRequest(request);
      await _loadDocuments();
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _docsError = '$e');
    }
  }

  Future<void> _showDocumentChunks(String documentId) async {
    final auth = ref.read(authClientProvider);
    final token = auth.state.token;
    final openclawId = auth.state.activeOpenClawId;
    if (token == null || token.isEmpty || openclawId == null || openclawId.isEmpty) return;

    try {
      final url =
          '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/lightrag-documents/${Uri.encodeQueryComponent(documentId)}/chunks';
      final request = html.HttpRequest();
      request.open('GET', url);
      request.setRequestHeader('Authorization', 'Bearer $token');
      final raw = await _sendRequest(request);
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final chunks = (decoded['chunks'] as List? ?? const []);
      if (!mounted) return;

      // ignore: use_build_context_synchronously
      await showDialog<void>(
        context: context,
        builder: (context) {
          final theme = Theme.of(context);
          final t = ShellTokens.of(context);
          return Dialog(
            backgroundColor: t.surfaceBase,
            shape: RoundedRectangleBorder(
              borderRadius: kShellBorderRadius,
              side: BorderSide(color: t.border, width: 0.5),
            ),
            child: Container(
              width: 720,
              height: 520,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'document chunks · ${chunks.length}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: t.fgPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: chunks.length,
                      itemBuilder: (context, index) {
                        final c = Map<String, dynamic>.from(chunks[index] as Map);
                        final text = (c['text'] ?? '').toString();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: t.surfaceCard,
                            border: Border.all(color: t.border, width: 0.5),
                            borderRadius: kShellBorderRadiusSm,
                          ),
                          child: Text(
                            text.length > 260 ? '${text.substring(0, 260)}…' : text,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: t.fgSecondary,
                              height: 1.35,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _docsError = '$e');
    }
  }

  Future<void> _loadWithParams({String? label}) async {
    final auth = ref.read(authClientProvider);
    final token = auth.state.token;
    final openclawId = auth.state.activeOpenClawId;
    if (token == null || token.isEmpty || openclawId == null || openclawId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'no active claw selected';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final query = <String, String>{
        if (label != null && label.isNotEmpty) 'label': label,
        'max_depth': _maxDepth.toString(),
        'max_nodes': _maxNodes.toString(),
      };
      final qs = query.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final url =
          '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/lightrag-graph${qs.isEmpty ? '' : '?$qs'}';

      final request = html.HttpRequest();
      request.open('GET', url);
      request.setRequestHeader('Authorization', 'Bearer $token');
      final response = await _sendRequest(request);
      final decoded = jsonDecode(response);
      if (!mounted) return;

      setState(() {
        final data = Map<String, dynamic>.from(decoded as Map);
        _labels = (data['labels'] as List?) ?? const [];
        _selectedLabel = data['selectedLabel']?.toString();
        _graph = Map<String, dynamic>.from((data['graph'] as Map?) ?? const {});
      });

      _refreshLocalSearch();
      _ensureSelectedNodeExists();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _remoteSearch() async {
    final query = _searchQuery.trim();
    if (query.length < 2) return;
    final auth = ref.read(authClientProvider);
    final token = auth.state.token;
    final openclawId = auth.state.activeOpenClawId;
    if (token == null || token.isEmpty || openclawId == null || openclawId.isEmpty) return;

    setState(() => _searchingRemote = true);
    try {
      final params = <String, String>{
        'q': query,
        if (_selectedLabel != null && _selectedLabel!.isNotEmpty) 'label': _selectedLabel!,
        'max_depth': _maxDepth.toString(),
        'max_nodes': _maxNodes.toString(),
        'limit': '30',
      };
      final qs = params.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');

      final url = '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/lightrag-search?$qs';
      final request = html.HttpRequest();
      request.open('GET', url);
      request.setRequestHeader('Authorization', 'Bearer $token');
      final response = await _sendRequest(request);
      final decoded = Map<String, dynamic>.from(jsonDecode(response) as Map);
      final remote = (decoded['results'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();

      if (!mounted) return;
      final merged = <String, Map<String, dynamic>>{
        for (final r in _searchResults) (r['id'] ?? '').toString(): r,
      };
      for (final r in remote) {
        final id = (r['id'] ?? '').toString();
        if (id.isEmpty) continue;
        merged[id] = {
          ...r,
          'score': (r['score'] as num?)?.toDouble() ?? 0.0,
          'source': 'remote',
        };
      }
      final items = merged.values.toList()
        ..sort((a, b) =>
            ((b['score'] as num?) ?? 0).compareTo((a['score'] as num?) ?? 0));

      setState(() {
        _searchResults = items.take(60).toList();
      });
    } catch (_) {
      // Keep local results if remote search fails.
    } finally {
      if (mounted) setState(() => _searchingRemote = false);
    }
  }

  void _debouncedRemoteSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), _remoteSearch);
  }


  Future<String> _sendRequest(html.HttpRequest request) {
    final completer = Completer<String>();
    request.onLoad.listen((_) {
      final status = request.status ?? 0;
      if (status >= 200 && status < 300) {
        completer.complete(request.responseText ?? '{}');
      } else {
        completer.completeError('HTTP $status: ${request.responseText}');
      }
    });
    request.onError.listen((_) => completer.completeError('request failed'));
    request.send();
    return completer.future;
  }

  Future<String> _sendRequestWithBody(html.HttpRequest request, dynamic body) {
    final completer = Completer<String>();
    request.onLoad.listen((_) {
      final status = request.status ?? 0;
      if (status >= 200 && status < 300) {
        completer.complete(request.responseText ?? '{}');
      } else {
        completer.completeError('HTTP $status: ${request.responseText}');
      }
    });
    request.onError.listen((_) => completer.completeError('request failed'));
    request.send(body);
    return completer.future;
  }

  List<Map<String, dynamic>> get _graphNodes {
    return (_graph?['nodes'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const [];
  }

  List<Map<String, dynamic>> get _graphEdges {
    return (_graph?['edges'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const [];
  }

  Set<String> get _entityKinds {
    final out = <String>{};
    for (final n in _graphNodes) {
      final kind = ((n['entity_type'] ?? n['kind']) ?? 'unknown').toString();
      out.add(kind);
    }
    return out;
  }

  ({List<Map<String, dynamic>> nodes, List<Map<String, dynamic>> edges})
      _computeVisibleGraph() {
    var nodes = _graphNodes;
    var edges = _graphEdges;

    if (_entityKindFilter != 'all') {
      nodes = nodes
          .where((n) =>
              (((n['entity_type'] ?? n['kind']) ?? 'unknown').toString() ==
                  _entityKindFilter))
          .toList();
      final allowed = nodes
          .map((n) => (n['id'] ?? n['identity'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
      edges = edges
          .where((e) =>
              allowed.contains((e['source'] ?? '').toString()) &&
              allowed.contains((e['target'] ?? '').toString()))
          .toList();
    }

    if (_neighborsOnly && _selectedNodeId != null && _selectedNodeId!.isNotEmpty) {
      final center = _selectedNodeId!;
      final hasCenter = nodes.any(
        (n) => (n['id'] ?? n['identity'] ?? '').toString() == center,
      );
      if (!hasCenter) {
        return (nodes: nodes, edges: edges);
      }
      final keep = <String>{center};
      for (final e in edges) {
        final s = (e['source'] ?? '').toString();
        final t = (e['target'] ?? '').toString();
        if (s == center) keep.add(t);
        if (t == center) keep.add(s);
      }
      nodes = nodes
          .where((n) => keep.contains((n['id'] ?? n['identity'] ?? '').toString()))
          .toList();
      edges = edges
          .where((e) {
            final s = (e['source'] ?? '').toString();
            final t = (e['target'] ?? '').toString();
            return keep.contains(s) && keep.contains(t);
          })
          .toList();
    }

    return (nodes: nodes, edges: edges);
  }

  void _refreshLocalSearch() {
    final edges = _graphEdges;
    final degree = <String, int>{};
    for (final e in edges) {
      final s = (e['source'] ?? '').toString();
      final t = (e['target'] ?? '').toString();
      if (s.isNotEmpty) degree[s] = (degree[s] ?? 0) + 1;
      if (t.isNotEmpty) degree[t] = (degree[t] ?? 0) + 1;
    }

    final q = _searchQuery.trim().toLowerCase();
    final scored = <Map<String, dynamic>>[];
    for (final n in _graphNodes) {
      final id = (n['id'] ?? n['identity'] ?? '').toString();
      if (id.isEmpty) continue;
      final labels = (n['labels'] as List?)?.map((e) => e.toString()).toList() ?? const [];
      final label = (labels.isNotEmpty ? labels.first : (n['label'] ?? id)).toString();
      final kind = ((n['entity_type'] ?? n['kind']) ?? 'unknown').toString();
      final preview = ((n['properties'] as Map?)?['description'] ??
              (n['metadata'] as Map?)?['preview'] ??
              '')
          .toString();

      var score = 0.0;
      if (q.isNotEmpty) {
        final candidates = [id, label, kind, preview];
        for (final c in candidates) {
          final v = c.toLowerCase();
          if (v == q) {
            score += 100;
          } else if (v.startsWith(q)) {
            score += 60;
          } else if (v.contains(q)) {
            score += 25;
          }
        }
      } else {
        score = (degree[id] ?? 0).toDouble();
      }
      if (score > 0) {
        score += (degree[id] ?? 0).clamp(0, 15);
        scored.add({
          'id': id,
          'label': label,
          'kind': kind,
          'preview': preview,
          'degree': degree[id] ?? 0,
          'score': score,
          'source': 'local',
        });
      }
    }

    scored.sort((a, b) =>
        ((b['score'] as num?) ?? 0).compareTo((a['score'] as num?) ?? 0));

    setState(() {
      _searchResults = scored.take(60).toList();
    });
  }

  void _ensureSelectedNodeExists() {
    if (_selectedNodeId == null || _selectedNodeId!.isEmpty) return;
    final exists = _graphNodes.any((n) =>
        (n['id'] ?? n['identity'] ?? '').toString() == _selectedNodeId);
    if (!exists) {
      setState(() {
        _selectedNodeId = null;
        _neighborsOnly = false;
      });
    }
  }

  void _selectNodeFromResult(String id) {
    if (id.isEmpty) return;
    final visibleNow = _computeVisibleGraph();
    final existsInVisible = visibleNow.nodes.any(
      (n) => (n['id'] ?? n['identity'] ?? '').toString() == id,
    );

    setState(() {
      _selectedNodeId = id;
      if (!existsInVisible) {
        _neighborsOnly = false;
        _entityKindFilter = 'all';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final visible = _computeVisibleGraph();
    final isTruncated = _graph?['is_truncated'] == true;
    final isGraphView = _activeView == 'graph';

    final selectedNode = _selectedNodeId == null
        ? null
        : _graphNodes.cast<Map<String, dynamic>?>().firstWhere(
              (n) => (n?['id'] ?? n?['identity'] ?? '').toString() == _selectedNodeId,
              orElse: () => null,
            );

    return Dialog(
      backgroundColor: t.surfaceBase,
      shape: RoundedRectangleBorder(
        borderRadius: kShellBorderRadius,
        side: BorderSide(color: t.border, width: 0.5),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.92,
        height: MediaQuery.of(context).size.height * 0.9,
        constraints: const BoxConstraints(maxWidth: 1380, maxHeight: 920),
        child: Column(
          children: [
            _buildHeader(context, t, theme, visible.nodes.length, visible.edges.length),
            if (isGraphView) _buildControls(context, t, theme) else _buildDocumentsControls(context, t, theme),
            Expanded(
              child: isGraphView
                  ? _loading
                      ? Center(
                          child: Text(
                            'loading graph...',
                            style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder),
                          ),
                        )
                      : _error != null
                          ? Center(
                              child: Text(
                                _error!,
                                style: theme.textTheme.bodyMedium?.copyWith(color: t.statusError),
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 7,
                                    child: _KnowledgeGraphCanvas(
                                      nodes: visible.nodes,
                                      edges: visible.edges,
                                      isTruncated: isTruncated,
                                    ),
                                  ),
                                  Container(width: 0.5, color: t.border),
                                  SizedBox(
                                    width: 300,
                                    child: _buildSidePanel(context, t, theme, selectedNode),
                                  ),
                                ],
                              ),
                            )
                  : _buildDocumentsBody(context, t, theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ShellTokens t,
    ThemeData theme,
    int nodeCount,
    int edgeCount,
  ) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Text(
            _activeView == 'graph' ? 'knowledge graph' : 'knowledge documents',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: t.fgPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _activeView == 'graph'
                ? '$nodeCount nodes · $edgeCount edges'
                : '${_documents.length} documents',
            style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
          ),
          const SizedBox(width: 10),
          _presetChip(
            context,
            t,
            theme,
            _activeView == 'graph' ? 'graph' : 'graph (off)',
            onTap: () => setState(() => _activeView = 'graph'),
          ),
          _presetChip(
            context,
            t,
            theme,
            _activeView == 'documents' ? 'documents' : 'documents (off)',
            onTap: () {
              setState(() => _activeView = 'documents');
              _loadDocuments();
            },
          ),
          const Spacer(),
          GestureDetector(
            onTap: _activeView == 'graph'
                ? (_loading ? null : _load)
                : (_docsLoading ? null : _loadDocuments),
            child: Text(
              _activeView == 'graph'
                  ? (_loading ? 'loading...' : 'refresh')
                  : (_docsLoading ? 'loading...' : 'refresh'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: (_activeView == 'graph' ? _loading : _docsLoading)
                    ? t.fgDisabled
                    : t.accentPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Icon(Icons.close, size: 14, color: t.fgMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, ShellTokens t, ThemeData theme) {
    final labels = _labels.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    final kinds = ['all', ..._entityKinds.toList()..sort()];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 230,
            child: _compactDropdown<String>(
              value: labels.contains(_selectedLabel)
                  ? _selectedLabel
                  : (labels.isNotEmpty ? labels.first : null),
              items: labels,
              onChanged: _loading
                  ? null
                  : (v) {
                      if (v == null) return;
                      _loadWithParams(label: v);
                    },
              t: t,
              theme: theme,
            ),
          ),
          SizedBox(
            width: 250,
            child: _compactInput(
              controller: _searchCtrl,
              hint: 'search nodes',
              t: t,
              theme: theme,
            ),
          ),
          _presetChip(
            context,
            t,
            theme,
            _neighborsOnly ? 'neighbors on' : 'neighbors off',
            onTap: () => setState(() => _neighborsOnly = !_neighborsOnly),
          ),
          _presetChip(
            context,
            t,
            theme,
            _showAdvanced ? 'hide advanced' : 'show advanced',
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          ),
          if (_searchingRemote)
            Text(
              'searching...',
              style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
            ),
          if (_showAdvanced) ...[
            SizedBox(
              width: 66,
              child: _compactDropdown<int>(
                value: _maxDepth,
                items: const [1, 2, 3, 4, 5],
                onChanged: _loading
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() => _maxDepth = v);
                        _load();
                      },
                t: t,
                theme: theme,
              ),
            ),
            SizedBox(
              width: 88,
              child: _compactDropdown<int>(
                value: _maxNodes,
                items: const [100, 250, 500, 1000, 1500],
                onChanged: _loading
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() => _maxNodes = v);
                        _load();
                      },
                t: t,
                theme: theme,
              ),
            ),
            SizedBox(
              width: 120,
              child: _compactDropdown<String>(
                value: kinds.contains(_entityKindFilter) ? _entityKindFilter : 'all',
                items: kinds,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _entityKindFilter = v);
                  _refreshLocalSearch();
                },
                t: t,
                theme: theme,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDocumentsControls(BuildContext context, ShellTokens t, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: _compactInput(
              controller: _docSearchCtrl,
              hint: 'search documents',
              t: t,
              theme: theme,
            ),
          ),
          SizedBox(
            width: 120,
            child: _compactDropdown<String>(
              value: _docStatusFilter,
              items: const ['all', 'uploaded', 'indexed', 'failed'],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _docStatusFilter = v);
                _loadDocuments();
              },
              t: t,
              theme: theme,
            ),
          ),
          SizedBox(
            width: 120,
            child: _compactDropdown<String>(
              value: _docTypeFilter,
              items: const ['all', 'other', 'handbook', 'tender'],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _docTypeFilter = v);
                _loadDocuments();
              },
              t: t,
              theme: theme,
            ),
          ),
          _presetChip(
            context,
            t,
            theme,
            _uploading ? 'uploading...' : 'upload document',
            onTap: _uploading ? null : _uploadDocument,
          ),
          _presetChip(
            context,
            t,
            theme,
            'apply filters',
            onTap: _loadDocuments,
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsBody(BuildContext context, ShellTokens t, ThemeData theme) {
    if (_docsLoading) {
      return Center(
        child: Text(
          'loading documents...',
          style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder),
        ),
      );
    }
    if (_docsError != null) {
      return Center(
        child: Text(
          _docsError!,
          style: theme.textTheme.bodyMedium?.copyWith(color: t.statusError),
        ),
      );
    }
    if (_documents.isEmpty) {
      return Center(
        child: Text(
          'no documents yet',
          style: theme.textTheme.bodyMedium?.copyWith(color: t.fgMuted),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: ListView.separated(
        itemCount: _documents.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = _documents[index];
          final documentId = (item['document_id'] ?? '').toString();
          final filename = (item['filename'] ?? '').toString();
          final status = (item['status'] ?? 'unknown').toString();
          final type = (item['document_type'] ?? 'other').toString();
          final chunkCount = (item['chunk_count'] as num?)?.toInt() ?? 0;
          final updatedAt = (item['updated_at'] ?? '').toString();
          final updatedShort = updatedAt.length >= 19 ? updatedAt.substring(0, 19) : updatedAt;

          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: t.surfaceCard,
              border: Border.all(color: t.border, width: 0.5),
              borderRadius: kShellBorderRadiusSm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        filename.isEmpty ? documentId : filename,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: t.fgPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$type · $status · $chunkCount chunks · $updatedShort',
                        style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _inlineAction(context, t, theme, 'ingest', onTap: () => _ingestDocument(documentId)),
                const SizedBox(width: 8),
                _inlineAction(context, t, theme, 'chunks', onTap: () => _showDocumentChunks(documentId)),
                const SizedBox(width: 8),
                _inlineAction(context, t, theme, 'delete', onTap: () => _deleteDocument(documentId), danger: true),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSidePanel(
    BuildContext context,
    ShellTokens t,
    ThemeData theme,
    Map<String, dynamic>? selectedNode,
  ) {
    final preview = ((selectedNode?['properties'] as Map?)?['description'] ??
            (selectedNode?['metadata'] as Map?)?['preview'] ??
            '')
        .toString();
    final kind = ((selectedNode?['entity_type'] ?? selectedNode?['kind']) ?? 'node').toString();
    final label = (((selectedNode?['labels'] as List?)?.first) ??
            selectedNode?['label'] ??
            selectedNode?['id'] ??
            '')
        .toString();

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _searchQuery.isEmpty ? 'top nodes' : 'search results (${_searchResults.length})',
            style: theme.textTheme.bodySmall?.copyWith(color: t.fgSecondary),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: t.border, width: 0.5),
                borderRadius: kShellBorderRadiusSm,
              ),
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final item = _searchResults[index];
                  final id = (item['id'] ?? '').toString();
                  final isSelected = id == _selectedNodeId;
                  return GestureDetector(
                    onTap: () => _selectNodeFromResult(id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: t.border, width: 0.5),
                        ),
                        color: isSelected
                            ? t.accentPrimary.withOpacity(0.12)
                            : Colors.transparent,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (item['label'] ?? id).toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isSelected ? t.fgPrimary : t.fgSecondary,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${item['kind'] ?? 'node'} · score ${(item['score'] as num?)?.toStringAsFixed(0) ?? '0'} · deg ${item['degree'] ?? 0}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: t.fgMuted,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'node inspector',
            style: theme.textTheme.bodySmall?.copyWith(color: t.fgSecondary),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _presetChip(context, t, theme, 'speed', onTap: () {
                setState(() {
                  _maxDepth = 2;
                  _maxNodes = 250;
                });
                _load();
              }),
              _presetChip(context, t, theme, 'detail', onTap: () {
                setState(() {
                  _maxDepth = 4;
                  _maxNodes = 1000;
                });
                _load();
              }),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 130),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: t.border, width: 0.5),
              borderRadius: kShellBorderRadiusSm,
              color: t.surfaceCard,
            ),
            child: selectedNode == null
                ? Text(
                    'select a search result to inspect',
                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: t.fgPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$kind · ${(selectedNode['id'] ?? '').toString()}',
                        style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
                      ),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        SelectableText(
                          preview,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: t.fgSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _compactInput({
    required TextEditingController controller,
    required String hint,
    required ShellTokens t,
    required ThemeData theme,
  }) {
    return TextField(
      controller: controller,
      style: theme.textTheme.labelSmall?.copyWith(color: t.fgPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: t.fgPlaceholder, fontSize: 11),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        enabledBorder: OutlineInputBorder(
          borderRadius: kShellBorderRadiusSm,
          borderSide: BorderSide(color: t.border, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: kShellBorderRadiusSm,
          borderSide: BorderSide(color: t.accentSecondary, width: 0.7),
        ),
      ),
    );
  }

  Widget _compactDropdown<T>({
    required T? value,
    required List<T> items,
    required ValueChanged<T?>? onChanged,
    required ShellTokens t,
    required ThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: t.border, width: 0.5),
        borderRadius: kShellBorderRadiusSm,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          menuMaxHeight: 280,
          dropdownColor: t.surfaceCard,
          iconEnabledColor: t.fgMuted,
          style: theme.textTheme.labelSmall?.copyWith(color: t.fgPrimary),
          selectedItemBuilder: (context) => items
              .map(
                (v) => Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    v.toString(),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgPrimary),
                  ),
                ),
              )
              .toList(),
          items: items
              .map((v) => DropdownMenuItem<T>(
                    value: v,
                    child: Text(
                      v.toString(),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: t.fgPrimary),
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _presetChip(
    BuildContext context,
    ShellTokens t,
    ThemeData theme,
    String label, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: kShellBorderRadiusSm,
            border: Border.all(color: t.border, width: 0.5),
            color: onTap == null ? t.surfaceCard : t.surfaceBase,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: onTap == null ? t.fgDisabled : t.fgMuted,
              fontSize: 10,
            ),
          ),
        ),
      ),
    );
  }

  Widget _inlineAction(
    BuildContext context,
    ShellTokens t,
    ThemeData theme,
    String label, {
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: danger ? t.statusError : t.accentPrimary,
          ),
        ),
      ),
    );
  }
}

class _KnowledgeGraphCanvas extends StatefulWidget {
  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> edges;
  final bool isTruncated;

  const _KnowledgeGraphCanvas({
    required this.nodes,
    required this.edges,
    this.isTruncated = false,
  });

  @override
  State<_KnowledgeGraphCanvas> createState() => _KnowledgeGraphCanvasState();
}

class _KnowledgeGraphCanvasState extends State<_KnowledgeGraphCanvas> {
  late ForceGraphController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
  }

  @override
  void didUpdateWidget(covariant _KnowledgeGraphCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodes != widget.nodes || oldWidget.edges != widget.edges) {
      _controller = _buildController();
    }
  }

  ForceGraphController _buildController() {
    final forceNodes = _toForceGraphNodes(widget.nodes, widget.edges);
    return ForceGraphController(nodes: forceNodes);
  }

  List<ForceGraphNodeData> _toForceGraphNodes(
    List<Map<String, dynamic>> nodes,
    List<Map<String, dynamic>> edges,
  ) {
    final nodeMap = <String, Map<String, dynamic>>{};
    for (final n in nodes) {
      final id = (n['id'] ?? n['identity'] ?? '').toString();
      if (id.isNotEmpty) nodeMap[id] = Map<String, dynamic>.from(n);
    }
    for (final e in edges) {
      final src = (e['source'] ?? '').toString();
      final tgt = (e['target'] ?? '').toString();
      if (src.isNotEmpty && !nodeMap.containsKey(src)) {
        nodeMap[src] = {'id': src, 'label': src, 'kind': 'unknown'};
      }
      if (tgt.isNotEmpty && !nodeMap.containsKey(tgt)) {
        nodeMap[tgt] = {'id': tgt, 'label': tgt, 'kind': 'unknown'};
      }
    }

    final outgoing = <String, List<ForceGraphEdgeData>>{};
    for (final e in edges) {
      final src = (e['source'] ?? '').toString();
      final tgt = (e['target'] ?? '').toString();
      if (src.isEmpty || tgt.isEmpty) continue;
      outgoing.putIfAbsent(src, () => []).add(
            ForceGraphEdgeData.from(
              source: src,
              target: tgt,
              similarity: 1.0,
              data: e,
            ),
          );
    }

    return nodeMap.entries.map((entry) {
      final id = entry.key;
      final raw = entry.value;
      final kind = ((raw['entity_type'] ?? raw['kind']) ?? 'node').toString();
      final label = ((raw['labels'] as List?)?.first ?? raw['label'] ?? raw['id'] ?? id)
          .toString();
      return ForceGraphNodeData.from(
        id: id,
        edges: outgoing[id] ?? [],
        title: label,
        data: raw,
        removable: false,
        radius: kind == 'chunk' ? 0.15 : 0.2,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    if (widget.nodes.isEmpty && widget.edges.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined, size: 44, color: t.fgMuted),
            const SizedBox(height: 10),
            Text(
              'no graph data',
              style: theme.textTheme.bodyMedium?.copyWith(color: t.fgMuted),
            ),
            Text(
              'adjust filters or ingest more documents',
              style: theme.textTheme.labelSmall?.copyWith(color: t.fgPlaceholder),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.isTruncated)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: t.statusWarning.withOpacity(0.15),
              border: Border.all(color: t.statusWarning.withOpacity(0.4), width: 0.5),
              borderRadius: kShellBorderRadiusSm,
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 13, color: t.statusWarning),
                const SizedBox(width: 6),
                Text(
                  'graph truncated — raise max nodes for broader context',
                  style: theme.textTheme.labelSmall?.copyWith(color: t.statusWarning),
                ),
              ],
            ),
          ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kShellRadius),
            child: ForceGraphWidget(
              controller: _controller,
              showControlBar: true,
              defaultControlBarForegroundColor: t.fgPrimary,
              defaultControlBarBackgroundColor: t.surfaceCard,
              nodeTooltipBuilder: (context, node) {
                final raw = node.data.data as Map<String, dynamic>?;
                if (raw == null) return Text(node.data.title);
                final kind = ((raw['entity_type'] ?? raw['kind']) ?? 'node').toString();
                final label =
                    ((raw['labels'] as List?)?.first ?? raw['label'] ?? raw['id'] ?? '').toString();
                final preview = ((raw['properties'] as Map?)?['description'] ??
                        (raw['metadata'] as Map?)?['preview'] ??
                        '')
                    .toString();
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$kind: $label', style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(preview, style: TextStyle(fontSize: 11, color: t.fgSecondary)),
                      ],
                    ],
                  ),
                );
              },
              edgeTooltipBuilder: (context, edge) {
                final raw = edge.data.data as Map<String, dynamic>?;
                final kind = raw?['kind'] ?? 'link';
                return Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text('${edge.data.source} → ${edge.data.target} ($kind)'),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
