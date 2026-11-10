import '../models/drawing_template.dart';

/// Session-scoped templates the picker shows in addition to the portal-managed
/// ones from `svg_assets`. Currently only holds templates the user uploads via
/// the picker's "Upload SVG" tile ([DrawingController.uploadSvgTemplate]); it
/// starts empty and is not persisted across launches.
final List<DrawingTemplate> kTemplates = <DrawingTemplate>[];
