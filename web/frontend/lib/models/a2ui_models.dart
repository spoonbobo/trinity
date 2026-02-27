/// A2UI v0.8 component models for rendering agent-driven UI surfaces.

class A2UISurface {
  final String surfaceId;
  final List<A2UIComponent> components;
  String? rootId;

  A2UISurface({
    required this.surfaceId,
    required this.components,
    this.rootId,
  });
}

class A2UIComponent {
  final String id;
  final String type;
  final Map<String, dynamic> props;

  const A2UIComponent({
    required this.id,
    required this.type,
    required this.props,
  });

  factory A2UIComponent.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final componentMap = json['component'] as Map<String, dynamic>;
    final type = componentMap.keys.first;
    final props = componentMap[type] as Map<String, dynamic>;
    return A2UIComponent(id: id, type: type, props: props);
  }
}

class SurfaceUpdate {
  final String surfaceId;
  final List<A2UIComponent> components;

  SurfaceUpdate({required this.surfaceId, required this.components});

  factory SurfaceUpdate.fromJson(Map<String, dynamic> json) {
    final surfaceId = json['surfaceId'] as String;
    final rawComponents = json['components'] as List<dynamic>;
    final components =
        rawComponents.map((c) => A2UIComponent.fromJson(c as Map<String, dynamic>)).toList();
    return SurfaceUpdate(surfaceId: surfaceId, components: components);
  }
}

class BeginRendering {
  final String surfaceId;
  final String root;

  BeginRendering({required this.surfaceId, required this.root});

  factory BeginRendering.fromJson(Map<String, dynamic> json) => BeginRendering(
        surfaceId: json['surfaceId'] as String,
        root: json['root'] as String,
      );
}

class DataModelUpdate {
  final String surfaceId;
  final Map<String, dynamic> data;

  DataModelUpdate({required this.surfaceId, required this.data});

  factory DataModelUpdate.fromJson(Map<String, dynamic> json) => DataModelUpdate(
        surfaceId: json['surfaceId'] as String,
        data: json['data'] as Map<String, dynamic>? ?? {},
      );
}

class DeleteSurface {
  final String surfaceId;

  DeleteSurface({required this.surfaceId});

  factory DeleteSurface.fromJson(Map<String, dynamic> json) =>
      DeleteSurface(surfaceId: json['surfaceId'] as String);
}
