/// One row from the Supabase `public.saved_drawings` table — a drawing the user
/// finished and saved. The PNG itself lives in the `saved_drawings` storage
/// bucket; [imageUrl] points at it.
///
/// See `supabase/saved_drawings.sql` for the schema and RLS (each user only
/// reads their own rows).
class SavedDrawing {
  const SavedDrawing({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.filePath,
    this.templateName,
    this.createdAt,
  });

  final String id;
  final String name;

  /// Public Storage URL the saved PNG is fetched from.
  final String imageUrl;

  /// Storage object path (`<auth-uid>/<timestamp>.png`) — used to remove the
  /// file when the drawing is deleted.
  final String filePath;

  /// The coloring template this drawing was made from, when it wasn't a free
  /// draw. Null for free-draw saves.
  final String? templateName;

  /// When the row was created (local time). Null if the column was missing or
  /// unparseable.
  final DateTime? createdAt;

  /// Builds a saved drawing from a Supabase row. Returns null when the row lacks
  /// the id / image URL it needs to be usable.
  static SavedDrawing? fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString();
    final url = (map['image_url'] as String?)?.trim();
    if (id == null || id.isEmpty || url == null || url.isEmpty) return null;

    final rawName = (map['name'] as String?)?.trim();
    final filePath = (map['file_path'] as String?)?.trim();
    final template = (map['template_name'] as String?)?.trim();
    final created = map['created_at'];

    return SavedDrawing(
      id: id,
      name: (rawName != null && rawName.isNotEmpty) ? rawName : 'My drawing',
      imageUrl: url,
      filePath: (filePath != null && filePath.isNotEmpty) ? filePath : '',
      templateName: (template != null && template.isNotEmpty) ? template : null,
      createdAt: created is String ? DateTime.tryParse(created)?.toLocal() : null,
    );
  }
}
