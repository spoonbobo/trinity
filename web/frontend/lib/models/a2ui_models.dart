/// A2UI v0.8 component models for rendering agent-driven UI surfaces.
///
/// Implements the full A2UI v0.8 specification including:
/// - Per-surface data model store with path-based get/set
/// - BoundValue resolution (literalString, literalNumber, literalBoolean, path)
/// - dataModelUpdate with adjacency-list contents parsing
/// - Structured userAction events

class A2UISurface {
  final String surfaceId;
  final Map<String, A2UIComponent> components;
  String? rootId;
  String? catalogId;

  /// Per-surface data model (A2UI v0.8 Section 4).
  final Map<String, dynamic> dataModel = {};

  A2UISurface({
    required this.surfaceId,
    Map<String, A2UIComponent>? components,
    this.rootId,
    this.catalogId,
  }) : components = components ?? {};

  /// Get a value from the data model by slash-delimited path (e.g. "/user/name").
  dynamic getPath(String path) {
    final segments = path
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    dynamic current = dataModel;
    for (final seg in segments) {
      if (current is Map<String, dynamic> && current.containsKey(seg)) {
        current = current[seg];
      } else {
        return null;
      }
    }
    return current;
  }

  /// Set a value in the data model by slash-delimited path.
  void setPath(String path, dynamic value) {
    final segments = path
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) return;

    Map<String, dynamic> current = dataModel;
    for (int i = 0; i < segments.length - 1; i++) {
      if (current[segments[i]] is! Map<String, dynamic>) {
        current[segments[i]] = <String, dynamic>{};
      }
      current = current[segments[i]] as Map<String, dynamic>;
    }
    current[segments.last] = value;
  }

  /// Merge adjacency-list contents into the data model at the given path.
  void mergeContents(String? path, List<dynamic> contents) {
    final target = <String, dynamic>{};
    _parseContents(contents, target);

    if (path == null || path.isEmpty) {
      // Replace/merge at root
      dataModel.addAll(target);
    } else {
      // Merge at the specified path
      final segments = path
          .split('/')
          .where((s) => s.isNotEmpty)
          .toList();
      Map<String, dynamic> current = dataModel;
      for (int i = 0; i < segments.length - 1; i++) {
        if (current[segments[i]] is! Map<String, dynamic>) {
          current[segments[i]] = <String, dynamic>{};
        }
        current = current[segments[i]] as Map<String, dynamic>;
      }
      final lastSeg = segments.last;
      if (current[lastSeg] is Map<String, dynamic>) {
        (current[lastSeg] as Map<String, dynamic>).addAll(target);
      } else {
        current[lastSeg] = target;
      }
    }
  }

  /// Parse adjacency-list contents array into a flat map.
  void _parseContents(List<dynamic> contents, Map<String, dynamic> target) {
    for (final entry in contents) {
      if (entry is! Map<String, dynamic>) continue;
      final key = entry['key'] as String?;
      if (key == null) continue;

      if (entry.containsKey('valueString')) {
        target[key] = entry['valueString'];
      } else if (entry.containsKey('valueNumber')) {
        target[key] = entry['valueNumber'];
      } else if (entry.containsKey('valueBoolean')) {
        target[key] = entry['valueBoolean'];
      } else if (entry.containsKey('valueMap')) {
        final nested = <String, dynamic>{};
        final valueMap = entry['valueMap'];
        if (valueMap is List) {
          _parseContents(valueMap, nested);
        }
        target[key] = nested;
      } else if (entry.containsKey('valueArray')) {
        target[key] = entry['valueArray'];
      }
    }
  }
}

class A2UIComponent {
  final String id;
  final String type;
  final Map<String, dynamic> props;
  final num? weight;

  const A2UIComponent({
    required this.id,
    required this.type,
    required this.props,
    this.weight,
  });

  factory A2UIComponent.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final weight = json['weight'] as num?;
    final componentRaw = json['component'];
    if (componentRaw is! Map<String, dynamic> || componentRaw.isEmpty) {
      return A2UIComponent(id: id, type: 'Unknown', props: {}, weight: weight);
    }
    final type = componentRaw.keys.first;
    final propsRaw = componentRaw[type];
    final props = propsRaw is Map<String, dynamic> ? propsRaw : <String, dynamic>{};
    return A2UIComponent(id: id, type: type, props: props, weight: weight);
  }
}

class SurfaceUpdate {
  final String surfaceId;
  final List<A2UIComponent> components;

  SurfaceUpdate({required this.surfaceId, required this.components});

  factory SurfaceUpdate.fromJson(Map<String, dynamic> json) {
    final surfaceId = json['surfaceId'] as String? ?? 'main';
    final rawComponents = json['components'] as List<dynamic>? ?? [];
    final components =
        rawComponents.map((c) => A2UIComponent.fromJson(c as Map<String, dynamic>)).toList();
    return SurfaceUpdate(surfaceId: surfaceId, components: components);
  }
}

class BeginRendering {
  final String surfaceId;
  final String root;
  final String? catalogId;

  BeginRendering({required this.surfaceId, required this.root, this.catalogId});

  factory BeginRendering.fromJson(Map<String, dynamic> json) => BeginRendering(
        surfaceId: json['surfaceId'] as String? ?? 'main',
        root: json['root'] as String? ?? '',
        catalogId: json['catalogId'] as String?,
      );
}

class DataModelUpdate {
  final String surfaceId;
  final String? path;
  final List<dynamic> contents;

  DataModelUpdate({required this.surfaceId, this.path, required this.contents});

  factory DataModelUpdate.fromJson(Map<String, dynamic> json) => DataModelUpdate(
        surfaceId: json['surfaceId'] as String? ?? 'main',
        path: json['path'] as String?,
        contents: json['contents'] as List<dynamic>? ?? [],
      );
}

class DeleteSurface {
  final String surfaceId;

  DeleteSurface({required this.surfaceId});

  factory DeleteSurface.fromJson(Map<String, dynamic> json) =>
      DeleteSurface(surfaceId: json['surfaceId'] as String? ?? 'main');
}

/// Structured user action event (A2UI v0.8 Section 5).
class UserAction {
  final String name;
  final String surfaceId;
  final String sourceComponentId;
  final String timestamp;
  final Map<String, dynamic> context;

  UserAction({
    required this.name,
    required this.surfaceId,
    required this.sourceComponentId,
    required this.timestamp,
    required this.context,
  });

  Map<String, dynamic> toJson() => {
        'userAction': {
          'name': name,
          'surfaceId': surfaceId,
          'sourceComponentId': sourceComponentId,
          'timestamp': timestamp,
          'context': context,
        },
      };
}

/// Resolve a BoundValue object from A2UI v0.8 spec.
/// Handles: literalString, literalNumber, literalBoolean, literalArray, path,
/// and the initialization shorthand (both path + literal).
dynamic resolveBoundValue(dynamic prop, A2UISurface? surface) {
  if (prop == null) return null;
  if (prop is String) return prop;
  if (prop is num) return prop;
  if (prop is bool) return prop;

  if (prop is Map) {
    final hasPath = prop.containsKey('path');
    final path = prop['path'] as String?;

    // Initialization shorthand: if both path and literal are present,
    // write the literal to the data model and bind to path.
    if (hasPath && path != null && surface != null) {
      final literal = prop['literalString'] ??
          prop['literalNumber'] ??
          prop['literalBoolean'] ??
          prop['literalArray'];
      if (literal != null) {
        // Initialize data model at path with literal value
        final existing = surface.getPath(path);
        if (existing == null) {
          surface.setPath(path, literal);
        }
      }
      // Resolve from data model
      final resolved = surface.getPath(path);
      if (resolved != null) return resolved;
      // Fallback to literal if path not yet in model
      return prop['literalString'] ??
          prop['literalNumber'] ??
          prop['literalBoolean'] ??
          prop['literalArray'];
    }

    // Path-only binding
    if (hasPath && path != null && surface != null) {
      return surface.getPath(path);
    }

    // Literal-only values
    if (prop.containsKey('literalString')) return prop['literalString'];
    if (prop.containsKey('literalNumber')) return prop['literalNumber'];
    if (prop.containsKey('literalBoolean')) return prop['literalBoolean'];
    if (prop.containsKey('literalArray')) return prop['literalArray'];

    // Legacy fallback
    if (prop.containsKey('value')) return prop['value'];

    return prop.toString();
  }

  return prop.toString();
}

/// Resolve a BoundValue to a String.
String resolveBoundString(dynamic prop, A2UISurface? surface) {
  final val = resolveBoundValue(prop, surface);
  if (val == null) return '';
  return val.toString();
}

/// Resolve a BoundValue to a num.
num? resolveBoundNum(dynamic prop, A2UISurface? surface) {
  final val = resolveBoundValue(prop, surface);
  if (val is num) return val;
  if (val is String) return num.tryParse(val);
  return null;
}

/// Resolve a BoundValue to a bool.
bool resolveBoundBool(dynamic prop, A2UISurface? surface) {
  final val = resolveBoundValue(prop, surface);
  if (val is bool) return val;
  if (val is String) return val.toLowerCase() == 'true';
  return false;
}
