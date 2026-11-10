import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/saved_drawing.dart';

/// Thrown when a save is attempted with no backend configured or no signed-in
/// user. Carries a concise, user-facing [message].
class SaveUnavailable implements Exception {
  const SaveUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Persists the user's finished drawings: uploads the rendered PNG to Supabase
/// Storage and records one row per save in `public.saved_drawings`.
///
/// Registered `permanent: true` in `main()`. Requires the schema, RLS and
/// storage policies in `supabase/saved_drawings.sql`. With no backend (or no
/// session) [save] throws [SaveUnavailable] so the caller can fall back to a
/// share-only flow.
class SavedDrawingService extends GetxService {
  static SavedDrawingService get to => Get.find();

  SupabaseClient get _client => Supabase.instance.client;

  bool get _configured => AppConfig.isSupabaseConfigured;

  /// Uploads [png] to `<auth-uid>/<timestamp>.png` and inserts a
  /// `saved_drawings` row for the signed-in user. Returns the public image URL.
  /// Throws [SaveUnavailable] when there is no backend / session, or rethrows a
  /// Storage / Postgrest error on failure.
  Future<String> save({
    required Uint8List png,
    String? name,
    String? templateName,
  }) async {
    if (!_configured) {
      throw const SaveUnavailable(
        'Saving needs the backend configured. Add your Supabase keys to .env.',
      );
    }
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const SaveUnavailable('Please sign in to save your drawing.');
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '${user.id}/$ts.png';
    final bucket = AppConfig.savedDrawingsBucket;

    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          png,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: true,
          ),
        );
    final url = _client.storage.from(bucket).getPublicUrl(path);

    await _client.from('saved_drawings').insert({
      'name': (name == null || name.isEmpty) ? 'My drawing' : name,
      'image_url': url,
      'file_path': path,
      if (templateName != null && templateName.isNotEmpty)
        'template_name': templateName,
    });

    return url;
  }

  /// Overwrites an existing saved drawing in place (used after "Repaint"):
  /// uploads the new render under a fresh path, repoints [original]'s row at it,
  /// then deletes the previous Storage object — so the gallery keeps one entry
  /// per drawing instead of accumulating a copy on every save, and the new
  /// public URL sidesteps any stale-thumbnail caching.
  ///
  /// Returns the new image URL and Storage path. Throws [SaveUnavailable] when
  /// there is no backend / session, or when the row couldn't be updated (e.g.
  /// the `saved_drawings_update_own` RLS policy hasn't been applied) — in which
  /// case the just-uploaded orphan is removed and the original is left intact.
  Future<({String url, String path})> update(
    SavedDrawing original, {
    required Uint8List png,
    String? name,
    String? templateName,
  }) async {
    if (!_configured) {
      throw const SaveUnavailable(
        'Saving needs the backend configured. Add your Supabase keys to .env.',
      );
    }
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const SaveUnavailable('Please sign in to save your drawing.');
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '${user.id}/$ts.png';
    final bucket = AppConfig.savedDrawingsBucket;

    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          png,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: true,
          ),
        );
    final url = _client.storage.from(bucket).getPublicUrl(path);

    final updated = await _client
        .from('saved_drawings')
        .update({
          'name': (name == null || name.isEmpty) ? original.name : name,
          'image_url': url,
          'file_path': path,
          if (templateName != null && templateName.isNotEmpty)
            'template_name': templateName,
        })
        .eq('id', original.id)
        .select('id')
        .maybeSingle();

    // RLS blocked the update (or the row is gone): undo the orphan upload and
    // fail rather than delete the original's still-referenced image.
    if (updated == null) {
      await _client.storage.from(bucket).remove([path]);
      throw const SaveUnavailable(
        'Could not update this drawing. Apply the saved_drawings UPDATE policy '
        'in supabase/saved_drawings.sql.',
      );
    }

    if (original.filePath.isNotEmpty && original.filePath != path) {
      await _client.storage.from(bucket).remove([original.filePath]);
    }

    return (url: url, path: path);
  }

  /// Fetches the signed-in user's saved drawings, newest first. Returns `[]`
  /// when there is no backend or no session (RLS already scopes the rows to the
  /// current user, so no explicit user filter is needed). Rethrows a Postgrest
  /// error so the caller can offer a retry.
  Future<List<SavedDrawing>> fetchSaved() async {
    if (!_configured) return const <SavedDrawing>[];
    if (_client.auth.currentUser == null) return const <SavedDrawing>[];

    final rows = await _client
        .from('saved_drawings')
        .select('id, name, image_url, file_path, template_name, created_at')
        .order('created_at', ascending: false);

    return rows
        .map(SavedDrawing.fromMap)
        .whereType<SavedDrawing>()
        .toList(growable: false);
  }

  /// Downloads a saved drawing's PNG and hands it to the system share sheet.
  /// [sharePositionOrigin] anchors the iOS / iPad popover (pass the Share
  /// button's global rect).
  Future<void> shareSaved(
    SavedDrawing drawing, {
    Rect? sharePositionOrigin,
  }) async {
    final res = await http.get(Uri.parse(drawing.imageUrl));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Download failed (HTTP ${res.statusCode}).');
    }
    await sharePngBytes(
      res.bodyBytes,
      sharePositionOrigin: sharePositionOrigin,
      name: 'my_drawing',
    );
  }

  /// Deletes a saved drawing: removes the Storage object then the table row.
  /// Throws [SaveUnavailable] when there is no backend / session.
  Future<void> deleteSaved(SavedDrawing drawing) async {
    if (!_configured) {
      throw const SaveUnavailable('Deleting needs the backend configured.');
    }
    if (_client.auth.currentUser == null) {
      throw const SaveUnavailable('Please sign in to manage your drawings.');
    }

    if (drawing.filePath.isNotEmpty) {
      await _client.storage
          .from(AppConfig.savedDrawingsBucket)
          .remove([drawing.filePath]);
    }
    await _client.from('saved_drawings').delete().eq('id', drawing.id);
  }

  /// Updates only the name of an existing saved drawing in the database.
  /// Does NOT touch the Storage object — just the `saved_drawings` table row.
  /// Throws [SaveUnavailable] when there is no backend / session.
  Future<void> rename(String id, String newName) async {
    if (!_configured) {
      throw const SaveUnavailable('Renaming needs the backend configured.');
    }
    if (_client.auth.currentUser == null) {
      throw const SaveUnavailable('Please sign in to manage your drawings.');
    }
    await _client
        .from('saved_drawings')
        .update({'name': newName})
        .eq('id', id);
  }
}

/// Writes [bytes] to a temporary PNG and hands it to the system share sheet.
///
/// [sharePositionOrigin] anchors the iOS / iPad popover (pass the share button's
/// global rect); a top-right fallback is used when it is null. Shared by the
/// canvas and the saved-drawing result screen.
Future<void> sharePngBytes(
  Uint8List bytes, {
  Rect? sharePositionOrigin,
  String name = 'draw_painter',
}) async {
  final tmp = await getTemporaryDirectory();
  final filename = '${name}_${DateTime.now().millisecondsSinceEpoch}.png';
  final file = File('${tmp.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);

  final view = ui.PlatformDispatcher.instance.implicitView;
  final origin =
      sharePositionOrigin ??
      (view == null
          ? const Rect.fromLTWH(0, 0, 1, 1)
          : Rect.fromLTWH(
              view.physicalSize.width / view.devicePixelRatio - 40,
              40,
              32,
              32,
            ));

  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'image/png', name: filename)],
    subject: 'Draw Painter',
    sharePositionOrigin: origin,
  );
}
