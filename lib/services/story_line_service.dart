import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/story_line.dart';

/// Reads portal-managed story line rows from Supabase `story_lines` table.
///
/// Registered `permanent: true` in `main()`. Returns empty lists when no backend
/// is configured so the app still runs offline.
class StoryLineService extends GetxService {
  static StoryLineService get to => Get.find();

  SupabaseClient get _client => Supabase.instance.client;

  bool get _configured => AppConfig.isSupabaseConfigured;

  Future<List<StoryLine>> fetch({String? category}) async {
    if (!_configured) return const <StoryLine>[];
    // select('*') so portal-managed columns (is_new, view_count, …) flow
    // through automatically once added — no code change needed per column.
    var query = _client.from('story_lines').select('*');
    if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }
    final rows = await query
        .order('is_active', ascending: false)
        .order('created_at', ascending: false);
    return rows
        .map(StoryLine.fromMap)
        .whereType<StoryLine>()
        .toList(growable: false);
  }

  Stream<List<StoryLine>> watch({String? category}) async* {
    if (!_configured) {
      yield const <StoryLine>[];
      return;
    }
    try {
      yield await fetch(category: category);
    } catch (_) {
      yield const <StoryLine>[];
    }

    var backoffMs = 2000;
    while (true) {
      try {
        final base = _client.from('story_lines').stream(primaryKey: ['id']);
        final stream = (category != null && category.isNotEmpty)
            ? base.eq('category', category)
            : base;
        yield* stream.map(_mapAndSort);
        return;
      } catch (_) {
        await Future<void>.delayed(Duration(milliseconds: backoffMs));
        backoffMs = (backoffMs * 2).clamp(2000, 30000);
        try {
          yield await fetch(category: category);
        } catch (_) {}
      }
    }
  }

  final Map<String, _LiveFeed> _live = <String, _LiveFeed>{};

  String _liveKey(String? category) => category ?? '';

  Stream<List<StoryLine>> live({String? category}) {
    final key = _liveKey(category);
    return (_live[key] ??= _LiveFeed(watch(category: category))).stream;
  }

  List<StoryLine>? lastOf({String? category}) =>
      _live[_liveKey(category)]?.last;

  Future<void> refreshLive({String? category}) async {
    final feed = _live[_liveKey(category)];
    if (feed == null) return;
    try {
      feed.add(await fetch(category: category));
    } catch (_) {}
  }

  // ---- Per-story photo counts (for the grid card "🖼 N" chip) ---------------

  /// Reactive map of `story_line_id` → number of `svg_assets` rows linked to it.
  /// The grid reads this via `Obx` so each card paints its photo count as soon
  /// as the single round-trip below resolves. Keyed by story id (globally
  /// unique), so counts for different categories coexist safely.
  final RxMap<String, int> assetCounts = <String, int>{}.obs;

  /// Per-category count slices. A recount of a category REPLACES its slice
  /// (rather than adding into a shared map), so pull-to-refresh can't make the
  /// counts accumulate/double. Flattened into [assetCounts] for the UI.
  final Map<String, Map<String, int>> _countsByCategory =
      <String, Map<String, int>>{};

  /// Categories already fetched in this session, so repeated widget builds
  /// don't re-fire the count query. A [force] refresh re-fetches regardless.
  final Set<String> _countedCategories = <String>{};

  /// Fetches, in one round-trip, how many `svg_assets` belong to each story in
  /// [category] and merges them into [assetCounts]. Idempotent per category
  /// unless [force] is true. No-op (leaves counts empty) when no backend is
  /// configured — mirrors [fetch]/[live]. Safe to call un-awaited from a build.
  Future<void> loadAssetCounts({String? category, bool force = false}) async {
    if (!_configured) return;
    // Each shelf card carries a concrete category; without one there's nothing
    // meaningful to count (and `eq` on '' would match nothing).
    if (category == null || category.isEmpty) return;
    if (!force && !_countedCategories.add(category)) return; // already loaded
    try {
      // Select only the FK column for the category; count client-side. Rows with
      // a null `story_line_id` are simply skipped below — no extra filter needed.
      final rows = await _client
          .from('svg_assets')
          .select('story_line_id')
          .eq('category', category);
      final fresh = <String, int>{};
      for (final row in rows) {
        final id = (row['story_line_id'] as String?)?.trim();
        if (id != null && id.isNotEmpty) {
          fresh[id] = (fresh[id] ?? 0) + 1;
        }
      }
      // Replace this category's slice, then flatten all slices into the
      // observable map (story ids are globally unique, so slices don't collide).
      _countsByCategory[category] = fresh;
      final merged = <String, int>{};
      for (final slice in _countsByCategory.values) {
        merged.addAll(slice);
      }
      assetCounts.value = merged;
    } catch (e) {
      debugPrint('loadAssetCounts failed: $e');
      // Leave whatever counts we already had; the grid just hides the chip.
    }
  }

  List<StoryLine> _mapAndSort(List<Map<String, dynamic>> rows) {
    final items = rows.map(StoryLine.fromMap).whereType<StoryLine>().toList();
    items.sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      final aDate = a.createdAt ?? DateTime(2000);
      final bDate = b.createdAt ?? DateTime(2000);
      return bDate.compareTo(aDate);
    });
    return items;
  }
}

class _LiveFeed {
  _LiveFeed(this._source);

  final Stream<List<StoryLine>> _source;
  final StreamController<List<StoryLine>> _hub =
      StreamController<List<StoryLine>>.broadcast();
  StreamSubscription<List<StoryLine>>? _sub;

  List<StoryLine>? last;

  Stream<List<StoryLine>> get stream {
    _sub ??= _source.listen(
      (data) {
        last = data;
        _hub.add(data);
      },
      onError: _hub.addError,
    );
    return _hub.stream;
  }

  void add(List<StoryLine> data) {
    last = data;
    _hub.add(data);
  }
}
