import 'dart:async';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/svg_asset.dart';

/// The `svg_assets.category` values that scope each surface's images. These must
/// match the portal exactly (the DB filter is case-sensitive). Change here to
/// repoint a surface at a different category.
abstract final class SvgAssetCategory {
  /// AR Drawing overlay presets.
  static const String drawing = 'Drawing';

  /// Painting coloring templates.
  static const String painting = 'Painting';

  /// Puzzle sample photos.
  static const String puzzle = 'Puzzle';
}

/// Reads portal-managed image rows from the Supabase `svg_assets` table.
///
/// Registered `permanent: true` in `main()`. Returns empty lists when no backend
/// is configured so the app still runs offline; a real backend/RLS error is
/// thrown so callers can surface a retry. Reads require the caller to be signed
/// in (RLS) — see `supabase/svg_assets_rls.sql`.
class SvgAssetService extends GetxService {
  static SvgAssetService get to => Get.find();

  SupabaseClient get _client => Supabase.instance.client;

  bool get _configured => AppConfig.isSupabaseConfigured;

  /// Fetches assets, optionally limited to one [category]. Returns **both**
  /// active and inactive rows so the galleries can show inactive ones as locked
  /// ([SvgAsset.isLocked]); active (free) rows are ordered first, then by
  /// category and name. Returns `[]` only when there is no backend.
  ///
  /// Pass [storyLineId] to narrow results to assets linked to a specific story.
  ///
  /// Reading inactive rows requires the RLS policy to allow it — see
  /// `supabase/svg_assets_rls.sql`.
  Future<List<SvgAsset>> fetch({String? category, String? storyLineId}) async {
    if (!_configured) return const <SvgAsset>[];
    var query = _client
        .from('svg_assets')
        .select('id, name, category, public_url, file_path, description, is_active, story_line_id');
    if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }
    if (storyLineId != null && storyLineId.isNotEmpty) {
      query = query.eq('story_line_id', storyLineId);
    }
    final rows = await query
        .order('is_active', ascending: false) // free items first
        .order('category')
        .order('name');
    return rows
        .map(SvgAsset.fromMap)
        .whereType<SvgAsset>()
        .toList(growable: false);
  }

  /// Live stream of assets for [category], updated in real time via Supabase
  /// Realtime: emits a REST snapshot immediately, then re-emits on every
  /// insert / update / delete (e.g. the portal toggling `is_active`). Active
  /// (free) rows are ordered first, then by category and name.
  ///
  /// Requires the `svg_assets` table to be in the `supabase_realtime`
  /// publication — see `supabase/svg_assets_realtime.sql`. With no backend it
  /// emits a single empty list. RLS still applies, so the stream only carries
  /// rows the signed-in user may read.
  ///
  /// Resilience: at cold start the stored access token may already be expired
  /// (it refreshes a moment later), and the realtime socket can connect with
  /// that stale token and fail with `InvalidJWTToken: Token has expired`. So we
  /// (a) yield an immediate REST snapshot — REST transparently uses the
  /// refreshed token, so images always appear — and (b) on a realtime error,
  /// wait for the refresh to land and re-subscribe with the fresh token,
  /// re-emitting a REST snapshot meanwhile. Once realtime is authenticated it
  /// stays connected and streams live updates as before.
  Stream<List<SvgAsset>> watch({String? category}) async* {
    if (!_configured) {
      yield const <SvgAsset>[];
      return;
    }
    // Immediate REST snapshot so the gallery paints even if realtime is briefly
    // unauthenticated.
    try {
      yield await fetch(category: category);
    } catch (_) {
      // Ignore — the realtime subscription below will supply data.
    }
    var backoffMs = 2000;
    while (true) {
      try {
        // `.stream()` returns a filter builder; `.eq()` narrows it to the base
        // stream builder — keep them as separate locals so the types line up.
        final base = _client.from('svg_assets').stream(primaryKey: ['id']);
        final stream = (category != null && category.isNotEmpty)
            ? base.eq('category', category)
            : base;
        // Blocks here streaming live updates until the socket errors or closes.
        yield* stream.map(_mapAndSort);
        return; // completed cleanly
      } catch (_) {
        // Realtime errored (commonly the cold-start expired JWT). Give the
        // session refresh time to propagate, refresh the snapshot, then retry.
        await Future<void>.delayed(Duration(milliseconds: backoffMs));
        backoffMs = (backoffMs * 2).clamp(2000, 30000);
        try {
          yield await fetch(category: category);
        } catch (_) {
          // Still unavailable — keep retrying realtime.
        }
      }
    }
  }

  // ---- Shared, re-listenable live feeds -------------------------------------

  /// Cached live feeds keyed by category (`''` = all). [watch] returns a
  /// *single-subscription* stream, so a `StreamBuilder` that gets disposed and
  /// rebuilt (e.g. a tab switching away and back) crashes trying to re-listen to
  /// it ("Stream has already been listened to"). [live] wraps one [watch]
  /// subscription per category in a broadcast hub so any number of widgets can
  /// listen — and re-listen — safely.
  final Map<String, _LiveFeed> _live = <String, _LiveFeed>{};

  String _liveKey(String? category) => category ?? '';

  /// Broadcast, re-listenable view of the realtime feed for [category]. Backed
  /// by a single [watch] subscription (so the cold-start JWT handling still
  /// applies) shared across the app. Pair with [lastOf] as
  /// `StreamBuilder.initialData` so a rebuilt listener paints the cached
  /// snapshot immediately instead of flashing a spinner.
  Stream<List<SvgAsset>> live({String? category}) {
    final key = _liveKey(category);
    return (_live[key] ??= _LiveFeed(watch(category: category))).stream;
  }

  /// The most recent snapshot delivered to [live] for [category], or `null` if
  /// nothing has arrived yet. Use as `StreamBuilder.initialData`.
  List<SvgAsset>? lastOf({String? category}) =>
      _live[_liveKey(category)]?.last;

  /// Pushes a one-off REST snapshot into the [live] feed for [category]. Backs
  /// pull-to-refresh as a manual fallback when Realtime isn't enabled on the
  /// table. No-op if [live] was never started for the category.
  Future<void> refreshLive({String? category}) async {
    final feed = _live[_liveKey(category)];
    if (feed == null) return;
    try {
      feed.add(await fetch(category: category));
    } catch (_) {
      // Still unavailable — the realtime subscription supplies data later.
    }
  }

  // ---- Content-based SVG detection -----------------------------------------

  /// Cache of resolved "is this an SVG?" answers, keyed by public URL, so the
  /// network probe runs at most once per asset.
  final Map<String, bool> _isSvgCache = <String, bool>{};

  /// Whether [asset] is a vector SVG (→ coloring template with region fill) vs a
  /// raster photo (→ color-over). [SvgAsset.isSvg] only inspects the file
  /// extension, which the portal sometimes omits — so for anything not obviously
  /// `.svg`/`.png`/… we probe the file's content-type (and sniff the first bytes
  /// as a fallback) once and cache it. This lets a genuine SVG stored without a
  /// `.svg` extension still open as a coloring page.
  Future<bool> resolveIsSvg(SvgAsset asset) async {
    final src =
        ((asset.filePath != null && asset.filePath!.isNotEmpty)
                ? asset.filePath!
                : asset.publicUrl)
            .toLowerCase()
            .split('?')
            .first;
    if (src.endsWith('.svg')) return true;
    const rasterExt = ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'];
    if (rasterExt.any(src.endsWith)) return false;

    // Probe the resolved (directly loadable) URL — publicUrl may be a Storage
    // path, not an absolute URL.
    final url = asset.resolvedUrl;
    final cached = _isSvgCache[url];
    if (cached != null) return cached;

    var result = false;
    try {
      final res = await http.get(Uri.parse(url));
      final contentType = (res.headers['content-type'] ?? '').toLowerCase();
      if (contentType.contains('svg')) {
        result = true;
      } else if (contentType.startsWith('image/')) {
        result = false;
      } else {
        // Unknown/generic content-type: sniff the opening bytes for an SVG tag.
        final body = res.bodyBytes;
        final n = body.length < 512 ? body.length : 512;
        final head = String.fromCharCodes(body.sublist(0, n)).toLowerCase();
        result = head.contains('<svg');
      }
    } catch (_) {
      result = false; // unreachable → treat as raster; color-over still works
    }
    _isSvgCache[url] = result;
    return result;
  }

  List<SvgAsset> _mapAndSort(List<Map<String, dynamic>> rows) {
    final assets =
        rows.map(SvgAsset.fromMap).whereType<SvgAsset>().toList();
    assets.sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1; // free first
      final byCategory = (a.category ?? '').compareTo(b.category ?? '');
      if (byCategory != 0) return byCategory;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return assets;
  }

  /// Like [fetch] but grouped by category (null/empty -> "Other"), preserving
  /// fetch order within each group. Insertion order of the returned map follows
  /// first appearance of each category.
  Future<Map<String, List<SvgAsset>>> fetchGrouped({String? category}) async {
    final assets = await fetch(category: category);
    final grouped = <String, List<SvgAsset>>{};
    for (final asset in assets) {
      final key = asset.category ?? 'Other';
      grouped.putIfAbsent(key, () => <SvgAsset>[]).add(asset);
    }
    return grouped;
  }
}

/// Fans a single-subscription source stream out to many (re-)listeners via a
/// broadcast hub, caching the latest value so a freshly mounted listener can
/// paint it immediately (see [SvgAssetService.lastOf]). The source subscription
/// is intentionally never cancelled: the owning service is `permanent`, so each
/// category keeps a single realtime subscription alive for the app's lifetime.
class _LiveFeed {
  _LiveFeed(this._source);

  final Stream<List<SvgAsset>> _source;
  final StreamController<List<SvgAsset>> _hub =
      StreamController<List<SvgAsset>>.broadcast();
  StreamSubscription<List<SvgAsset>>? _sub;

  /// Latest snapshot seen, for `initialData` on a (re)mounted listener.
  List<SvgAsset>? last;

  /// Broadcast stream; subscribes to the source lazily on first access.
  Stream<List<SvgAsset>> get stream {
    _sub ??= _source.listen(
      (data) {
        last = data;
        _hub.add(data);
      },
      onError: _hub.addError,
    );
    return _hub.stream;
  }

  /// Injects a snapshot (e.g. a pull-to-refresh REST fetch) into the hub.
  void add(List<SvgAsset> data) {
    last = data;
    _hub.add(data);
  }
}
