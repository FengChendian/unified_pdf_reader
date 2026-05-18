import 'package:flutter/material.dart';

class SelectionHighlightPainter extends CustomPainter {
  final List<Rect> rects;

  const SelectionHighlightPainter({required this.rects});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x552563EB)
      ..style = PaintingStyle.fill;

    for (final r in rects) {
      canvas.drawRect(r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SelectionHighlightPainter oldDelegate) {
    return oldDelegate.rects != rects;
  }
}
