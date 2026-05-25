import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yammopatinerapp/main.dart';

void main() {
  testWidgets('Draw Painter app renders core controls', (tester) async {
    await tester.pumpWidget(const DrawPainterApp());

    expect(find.text('Draw Painter'), findsOneWidget);
    expect(find.byIcon(Icons.undo), findsOneWidget);
    expect(find.byIcon(Icons.redo), findsOneWidget);
    // Clear lives in the overflow menu now; assert the menu trigger.
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });
}
