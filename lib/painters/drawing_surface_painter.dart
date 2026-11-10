import 'package:flutter/material.dart';

class DrawingSurfacePainter extends CustomPainter {
  DrawingSurfacePainter({
    this.crosshairOffset,
  });

  final Offset? crosshairOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;
    for (double x = 0; x <= size.width; x += 20) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += 20) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final crosshairPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..strokeWidth = 1.5;
    final cx = crosshairOffset?.dx ?? size.width / 2;
    final cy = crosshairOffset?.dy ?? size.height / 2;
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), crosshairPaint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), crosshairPaint);

    final borderPaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      borderPaint,
    );
    final cornerPaint = Paint()
      ..color = Colors.black45
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final cl = 20.0;
    canvas.drawLine(Offset(0, cl), Offset(0, 0), cornerPaint);
    canvas.drawLine(Offset(0, 0), Offset(cl, 0), cornerPaint);
    canvas.drawLine(
      Offset(size.width - cl, 0),
      Offset(size.width, 0),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, cl),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(size.width, size.height - cl),
      Offset(size.width, size.height),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - cl, size.height),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(cl, size.height),
      Offset(0, size.height),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(0, size.height - cl),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant DrawingSurfacePainter oldDelegate) =>
      oldDelegate.crosshairOffset != crosshairOffset;
}
