import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/story_line.dart';
import '../screens/story_detail_screen.dart';
import '../services/story_line_service.dart';
import '../theme/app_dimens.dart';
import '../theme/app_gradients.dart';
import '../theme/app_surfaces.dart';
import '../utils/page_transitions.dart';
import 'common/common.dart';

/// The stories-first home body shared by the AR and Puzzle tabs: a pull-to-
/// refresh list whose single child is a [StoryShelf] grid. (The Library composes
/// its own drawings row + a [StoryShelf].) Tapping a card opens
/// [StoryDetailScreen].
class StoryShelves extends StatelessWidget {
  const StoryShelves({
    super.key,
    required this.category,
    this.showHeader = true,
  });

  final String category;

  /// Whether to render the [StoryShelf]'s title header. AR & Puzzle hide it so
  /// their grid starts flush at the top.
  final bool showHeader;

  Future<void> _refresh() async {
    // Re-snapshot the live feed and the per-story photo counts together so the
    // grid refreshes in full on pull.
    await Future.wait([
      StoryLineService.to.refreshLive(category: category),
      StoryLineService.to.loadAssetCounts(category: category, force: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          StoryShelf(
            title: 'Stories',
            category: category,
            showHeader: showHeader,
          ),
        ],
      ),
    );
  }
}

/// A titled **2-column grid** of compact [StoryCard]s for [category], backed by
/// the live story feed ([StoryLineService.live]) and the per-story photo-count
/// map ([StoryLineService.assetCounts]). Non-scrolling (a [Wrap]) so it stays a
/// valid child of the host screens' `ListView`s.
class StoryShelf extends StatelessWidget {
  const StoryShelf({
    super.key,
    required this.title,
    required this.category,
    this.emptyText,
    this.showCount = true,
    this.showHeader = true,
  });

  final String title;
  final String category;

  /// Override for the empty-state caption (defaults to "No stories yet").
  final String? emptyText;

  /// Whether to show the story count next to the title. Some shelves (e.g. the
  /// Painting tab) prefer a clean header with no count.
  final bool showCount;

  /// Whether to render the title header at all. AR & Puzzle hide it.
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StoryLine>>(
      stream: StoryLineService.to.live(category: category),
      initialData: StoryLineService.to.lastOf(category: category),
      builder: (context, snap) {
        final loading =
            snap.connectionState == ConnectionState.waiting && !snap.hasData;
        final stories = snap.data ?? const <StoryLine>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showHeader) ...[
              ShelfHeader(
                title,
                count: showCount && stories.isNotEmpty ? stories.length : null,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (loading)
              const _GridSkeleton()
            else if (stories.isEmpty)
              _EmptyShelf(emptyText ?? 'No stories yet')
            else
              _StoryGrid(stories: stories, category: category),
          ],
        );
      },
    );
  }
}

/// Responsive grid of [StoryCard]s. Loads photo counts for [category] once on
/// mount; an [Obx] repaints the count chips the moment they land.
class _StoryGrid extends StatefulWidget {
  const _StoryGrid({required this.stories, required this.category});

  final List<StoryLine> stories;
  final String category;

  @override
  State<_StoryGrid> createState() => _StoryGridState();
}

class _StoryGridState extends State<_StoryGrid> {
  @override
  void initState() {
    super.initState();
    // Idempotent per category (guarded in the service) — fires once a session.
    unawaited(StoryLineService.to.loadAssetCounts(category: widget.category));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = AppSpacing.md;
        final cols = _columnsFor(constraints.maxWidth);
        final cardWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;
        return Obx(() {
          final counts = StoryLineService.to.assetCounts;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final story in widget.stories)
                SizedBox(
                  width: cardWidth,
                  child: StoryCard(
                    story: story,
                    photoCount: counts[story.id],
                    onTap: () => Navigator.of(context).push(
                      FadeSlideRoute<void>(
                        builder: (_) => StoryDetailScreen(story: story),
                      ),
                    ),
                  ),
                ),
            ],
          );
        });
      },
    );
  }
}

/// Grid-shaped loading placeholder that mirrors [_StoryGrid]'s column math.
class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = AppSpacing.md;
        final cols = _columnsFor(constraints.maxWidth);
        final cardWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < cols * 2; i++)
              SizedBox(
                width: cardWidth,
                child: const StoryCardSkeleton(compact: true),
              ),
          ],
        );
      },
    );
  }
}

int _columnsFor(double width) {
  if (width < 600) return 2;
  if (width < 1000) return 3;
  return 4;
}

/// Whether [url] points at a vector SVG (vs a raster photo). Ignores any
/// `?query` suffix — mirrors [SvgAsset.isSvg].
bool _isSvgUrl(String url) =>
    url.toLowerCase().split('?').first.endsWith('.svg');

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              color: scheme.onSurfaceVariant,
              size: 30,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact square story card: a cover image carrying the NEW badge and a
/// photo-count chip (image-only — no title text). Scales on tap.
class StoryCard extends StatelessWidget {
  const StoryCard({
    super.key,
    required this.story,
    this.photoCount,
    required this.onTap,
  });

  final StoryLine story;

  /// Number of photos inside this story, from [StoryLineService.assetCounts].
  /// Null while the count query is in flight (chip hidden).
  final int? photoCount;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = story.displayImageUrl;
    // Painting covers are SVG templates — render whole (contain) so the line
    // art isn't cropped; AR/Puzzle covers are raster photos — fill (cover).
    final coverFit =
        _isSvgUrl(url) ? BoxFit.contain : BoxFit.cover;
    return Pressable(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: cardSurface(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (url.isNotEmpty)
                    NetworkAssetImage(url: url, fit: coverFit)
                  else
                    DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: AppGradients.button,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.auto_stories_rounded,
                          color: Colors.white.withValues(alpha: 0.8),
                          size: 32,
                        ),
                      ),
                    ),
                  if (photoCount != null)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: _OverlayChip(
                        icon: Icons.collections_rounded,
                        label: '$photoCount',
                      ),
                    ),
                  if (story.isNew) const NewBadge(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Semi-transparent pill over the cover (photo count), readable on any image.
class _OverlayChip extends StatelessWidget {
  const _OverlayChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
