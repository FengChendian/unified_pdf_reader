import 'package:flutter/material.dart';
import '../utils/text_selection.dart';

class SelectionHighlightPainter extends CustomPainter {
  final List<HighlightRect> rects;

  const SelectionHighlightPainter({required this.rects});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x552563EB)
      ..style = PaintingStyle.fill;

    for (final hr in rects) {
      canvas.drawRect(hr.toRect(), paint);
    }
  }

  @override
  bool shouldRepaint(covariant SelectionHighlightPainter oldDelegate) {
    return oldDelegate.rects != rects;
  }
}
