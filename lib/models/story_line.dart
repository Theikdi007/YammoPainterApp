import '../config/app_config.dart';

class StoryLine {
  StoryLine({
    required this.id,
    required this.title,
    this.description = '',
    required this.category,
    required this.targetApp,
    required this.imagePath,
    this.imageUrl = '',
    this.isActive = true,
    this.createdAt,
    this.isNewFlag,
    this.viewCount,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final String targetApp;
  final String imagePath;
  final String imageUrl;
  final bool isActive;
  final DateTime? createdAt;

  /// Portal-controlled NEW flag from the `story_lines.is_new` column. When
  /// present (non-null) it drives [isNew] exactly — the portal decides which
  /// stories are flagged. Null only while the column hasn't been added yet, in
  /// which case [isNew] falls back to the [createdAt] recency rule.
  final bool? isNewFlag;

  /// Real portal view/paint count from the `story_lines.view_count` column.
  /// Null when the column is absent or unset — the grid card hides the
  /// popularity chip in that case (no client-derived/fake numbers).
  final int? viewCount;

  bool get isLocked => !isActive;

  bool get isNew {
    if (isNewFlag != null) return isNewFlag!; // real portal data wins
    if (createdAt == null) return false; // pre-migration fallback: recency
    return DateTime.now().difference(createdAt!).inDays < 7;
  }

  /// The fully-qualified, directly loadable URL for the story's cover image.
  ///
  /// `image_url` wins when present (already absolute). Otherwise the
  /// `image_path` column — a Storage object *path* (e.g.
  /// `story-covers/painting-01.svg`) — is resolved against the public Storage
  /// endpoint (`{supabaseUrl}/storage/v1/object/public/{svgBucket}/…`), the
  /// same way [SvgAsset.resolvedUrl] does. Without this the raw relative path
  /// flows straight to `Image`/`flutter_svg` network loaders in
  /// [NetworkAssetImage] and the cover never renders — the symptom where the
  /// top image on Painting / AR Drawing / Puzzle story cards stays blank.
  /// Absolute URLs pass through; with no backend configured the raw value is
  /// returned as-is.
  String get displayImageUrl {
    final value = (imageUrl.isNotEmpty ? imageUrl : imagePath).trim();
    if (value.isEmpty) return value;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    final base = AppConfig.supabaseUrl;
    if (base.isEmpty) return value;
    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final path = value.startsWith('/') ? value.substring(1) : value;
    return '$root/storage/v1/object/public/${AppConfig.svgBucket}/$path';
  }

  /// Short popularity label (e.g. `1.2k`, `940`) from a **real** [viewCount],
  /// or null when there's no real data — the card then hides the chip.
  String? get popularityLabel =>
      viewCount != null ? _formatCount(viewCount!) : null;

  /// Formats a count as a compact label: `940`, `1.2k`, `12k`.
  static String _formatCount(int n) {
    if (n < 1000) return '$n';
    final k = n / 1000;
    return k >= 10
        ? '${k.round()}k'
        : '${k.toStringAsFixed(1)}k'; // e.g. 1.2k
  }

  static StoryLine? fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString();
    final title = (map['title'] as String?)?.trim();
    if (id == null || id.isEmpty || title == null || title.isEmpty) return null;

    return StoryLine(
      id: id,
      title: title,
      description: (map['description'] as String?)?.trim() ?? '',
      category: (map['category'] as String?)?.trim() ?? '',
      targetApp: (map['target_app'] as String?)?.trim() ?? '',
      imagePath: (map['image_path'] as String?)?.trim() ?? '',
      imageUrl: (map['image_url'] as String?)?.trim() ?? '',
      isActive: map['is_active'] as bool? ?? true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      isNewFlag: map['is_new'] as bool?,
      viewCount: (map['view_count'] as num?)?.toInt(),
    );
  }
}
