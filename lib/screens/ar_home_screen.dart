import 'package:flutter/material.dart';

import '../services/svg_asset_service.dart';
import '../theme/app_surfaces.dart';
import '../widgets/common/common.dart';
import '../widgets/story_shelves.dart';

/// The **AR Drawing** tab. Stories-first: pick a story → its photos → tap one
/// to project it over the live camera (the open action lives in
/// [StoryDetailScreen]).
class ArHomeScreen extends StatelessWidget {
  const ArHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageSurface(context),
      appBar: const GradientAppBar(
        titleWidget: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_in_ar_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('AR Drawing'),
          ],
        ),
        actions: [NotificationBell()],
      ),
      body: SafeArea(
        child: StoryShelves(
          category: SvgAssetCategory.drawing,
          showHeader: false,
        ),
      ),
    );
  }
}
