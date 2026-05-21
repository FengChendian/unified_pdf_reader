import 'package:flutter/material.dart';

class HighlightPainter extends CustomPainter {
  final List<Rect> rects;
  final Color color;
  final double borderRadius;

  const HighlightPainter({
    required this.rects,
    this.color = const Color.fromARGB(99, 102, 184, 255),
    this.borderRadius = 6.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.multiply; // 乘法混合，叠加高亮颜色

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
