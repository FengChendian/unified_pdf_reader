import 'package:flutter/material.dart';

class HighlightPainter extends CustomPainter {
  final List<Rect> rects;
  final Color color;
  final double borderRadius;

  const HighlightPainter({
    required this.rects,
    this.color = const Color(0x55FFEB3B),
    this.borderRadius = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final rect in rects) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(borderRadius)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant HighlightPainter oldDelegate) {
    return oldDelegate.rects != rects ||
        oldDelegate.color != color ||
        oldDelegate.borderRadius != borderRadius;
  }
}
