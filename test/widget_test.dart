import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:pandapainterapp/main.dart';
import 'package:pandapainterapp/services/auth_service.dart';
import 'package:pandapainterapp/services/svg_asset_service.dart';

void main() {
  // main() registers these before runApp; the widget tests pump DrawPainterApp
  // directly, so they have to register the same services. With no SUPABASE_*
  // env in tests AuthService stays unconfigured (gate shows the app shell) and
  // SvgAssetService.fetch returns empty lists.
  setUp(() {
    Get.put(AuthService(), permanent: true);
    Get.put(SvgAssetService(), permanent: true);
  });
  tearDown(Get.reset);

  testWidgets('App shows the navigation destinations', (tester) async {
    await tester.pumpWidget(const DrawPainterApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final nav = find.byType(NavigationBar);
    expect(nav, findsOneWidget);
    // Scope to the NavigationBar so we don't collide with screen titles that
    // share these labels (every tab is mounted at once inside an IndexedStack).
    expect(
      find.descendant(of: nav, matching: find.text('Painting')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: nav, matching: find.text('AR Drawing')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: nav, matching: find.text('Puzzle')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: nav, matching: find.text('Account')),
      findsOneWidget,
    );
  });

  testWidgets('Painting tab shows its home, and Free Draw opens the canvas', (
    tester,
  ) async {
    // The app has perpetual animations (AR screen, loading spinners), so use
    // explicit pumps instead of pumpAndSettle, which would time out.
    await tester.pumpWidget(const DrawPainterApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Painting is the default (index 0) tab: its home greets with the hero and
    // a Free Draw entry tile.
    expect(find.text('Create & Color'), findsOneWidget);
    expect(find.text('Free Draw'), findsOneWidget);

    // Opening Free Draw pushes the canvas, which exposes the core controls.
    await tester.tap(find.text('Free Draw'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byIcon(Icons.undo), findsOneWidget);
    expect(find.byIcon(Icons.redo), findsOneWidget);
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
    expect(find.byType(Slider), findsWidgets);
  });

  testWidgets('Selecting tabs updates the navigation', (tester) async {
    await tester.pumpWidget(const DrawPainterApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final nav = find.byType(NavigationBar);
    // Default lands on Painting (index 0).
    expect(tester.widget<NavigationBar>(nav).selectedIndex, 0);

    await tester.tap(find.descendant(of: nav, matching: find.text('Puzzle')));
    await tester.pump();
    expect(tester.widget<NavigationBar>(nav).selectedIndex, 2);

    await tester.tap(find.descendant(of: nav, matching: find.text('Painting')));
    await tester.pump();
    expect(tester.widget<NavigationBar>(nav).selectedIndex, 0);
  });
}
