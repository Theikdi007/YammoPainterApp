import '../config/app_config.dart';

/// A portal-managed image row from the Supabase `svg_assets` table.
///
/// The bytes themselves live in Supabase Storage; [publicUrl] points at them.
/// These rows are the single source for AR overlay presets, painting templates,
/// and puzzle sample photos — replacing the previously bundled asset files.
class SvgAsset {
  SvgAsset({
    required this.id,
    required this.name,
    required this.publicUrl,
    this.category,
    this.filePath,
    this.description,
    this.createdAt,
    this.isActive = true,
    this.storyLineId,
  });

  /// True when the asset was created within the last 7 days.
  bool get isNew {
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt!).inDays < 7;
  }

  final String id;
  final String name;

  /// Public Storage URL the image is fetched from.
  final String publicUrl;

  /// Portal-defined grouping (e.g. preset category). Null/empty groups under
  /// "Other" in the UI.
  final String? category;

  /// Storage object path (e.g. `presets/bird.svg`); used as a secondary signal
  /// for [isSvg] when the URL has no extension.
  final String? filePath;
  final String? description;

  /// Supabase row creation timestamp. Used to determine if the asset is "new"
  /// (uploaded within the last 7 days).
  final DateTime? createdAt;

  /// Portal `is_active` flag. Active rows are free to use; inactive rows are
  /// shown **locked** in the galleries (not usable until activated). Defaults
  /// to true so a missing column never locks everything.
  final bool isActive;

  /// Inverse of [isActive] — locked content the user can't open yet.
  bool get isLocked => !isActive;

  /// True when the asset is a vector SVG (render with `flutter_svg`) rather than
  /// a raster photo (render with `Image`). Decided by file extension, ignoring
  /// any `?query` suffix on the URL.
  bool get isSvg {
    final source = (filePath != null && filePath!.isNotEmpty)
        ? filePath!
        : publicUrl;
    return source.toLowerCase().split('?').first.endsWith('.svg');
  }

  /// The fully-qualified, directly loadable URL for this asset's image.
  ///
  /// Portal rows sometimes store a Storage object *path* (e.g.
  /// `Drawing/bird.png`) in [publicUrl] instead of an absolute URL, which the
  /// `Image` / `flutter_svg` network loaders can't fetch. This resolves such
  /// paths against the public Storage endpoint
  /// (`{supabaseUrl}/storage/v1/object/public/{svgBucket}/…`) so every renderer
  /// — the galleries, the SVG content probe, and the open/load handlers — hits a
  /// real image. Absolute URLs are returned unchanged; with no backend
  /// configured the raw value is returned as-is.
  String get resolvedUrl {
    final raw = publicUrl.trim();
    if (raw.isEmpty) return raw;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = AppConfig.supabaseUrl;
    if (base.isEmpty) return raw;
    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final path = raw.startsWith('/') ? raw.substring(1) : raw;
    return '$root/storage/v1/object/public/${AppConfig.svgBucket}/$path';
  }

  /// The story line this asset belongs to (nullable FK → public.story_lines).
  final String? storyLineId;

  /// Builds an asset from a Supabase row. Returns null when the row lacks the
  /// id or public_url it needs to be usable.

  static SvgAsset? fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString();
    final url = (map['public_url'] as String?)?.trim();
    if (id == null || id.isEmpty || url == null || url.isEmpty) return null;

    final rawName = (map['name'] as String?)?.trim();
    final category = (map['category'] as String?)?.trim();
    final filePath = (map['file_path'] as String?)?.trim();
    final description = (map['description'] as String?)?.trim();

    return SvgAsset(
      id: id,
      name: (rawName != null && rawName.isNotEmpty) ? rawName : 'Untitled',
      publicUrl: url,
      category: (category != null && category.isNotEmpty) ? category : null,
      filePath: (filePath != null && filePath.isNotEmpty) ? filePath : null,
      description: (description != null && description.isNotEmpty)
          ? description
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      // Absent column ⇒ treat as active (free), never silently lock everything.
      isActive: map['is_active'] as bool? ?? true,
      storyLineId: (map['story_line_id'] as String?)?.trim(),
    );
  }
}
