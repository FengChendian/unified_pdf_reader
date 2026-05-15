import 'dart:ui';
import '../mupdf/mupdf.dart';

/// 唯一标识结构化文本中的一个字符
class CharPosition {
  final int blockIndex;
  final int lineIndex;
  final int charIndex;

  const CharPosition({
    required this.blockIndex,
    required this.lineIndex,
    required this.charIndex,
  });

  int compareTo(CharPosition other) {
    if (blockIndex != other.blockIndex) return blockIndex.compareTo(other.blockIndex);
    if (lineIndex != other.lineIndex) return lineIndex.compareTo(other.lineIndex);
    return charIndex.compareTo(other.charIndex);
  }

  bool operator <(CharPosition other) => compareTo(other) < 0;
  bool operator <=(CharPosition other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is CharPosition &&
      blockIndex == other.blockIndex &&
      lineIndex == other.lineIndex &&
      charIndex == other.charIndex;

  @override
  int get hashCode => Object.hash(blockIndex, lineIndex, charIndex);
}

/// 高亮矩形，坐标在 widget 逻辑像素空间
class HighlightRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const HighlightRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  Rect toRect() => Rect.fromLTRB(left, top, right, bottom);
}

/// 单页的完整选择状态
class PageTextSelection {
  final String text;
  final List<HighlightRect> highlightRects;
  final CharPosition startPosition;
  final CharPosition endPosition;
  final double scale;

  const PageTextSelection({
    required this.text,
    required this.highlightRects,
    required this.startPosition,
    required this.endPosition,
    required this.scale,
  });

  bool get isEmpty => text.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is PageTextSelection &&
      startPosition == other.startPosition &&
      endPosition == other.endPosition;

  @override
  int get hashCode => Object.hash(startPosition, endPosition);
}

/// 扁平化字符（供算法和缓存使用）
class FlatChar {
  final int blockIndex;
  final int lineIndex;
  final int charIndex;
  final double x0, y0, x1, y1;
  final String character;
  const FlatChar({
    required this.blockIndex,
    required this.lineIndex,
    required this.charIndex,
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    required this.character,
  });
}

/// 扁平化文本行（供算法和缓存使用）
class FlatLine {
  final int blockIndex;
  final int lineIndex;
  final double x0, x1;
  final double y0, y1;
  final List<FlatChar> chars;
  const FlatLine({
    required this.blockIndex,
    required this.lineIndex,
    required this.x0,
    required this.x1,
    required this.y0,
    required this.y1,
    required this.chars,
  });
}

/// 文本选择算法 — 坐标映射、字符查找、选区构建
class TextSelectionAlgorithm {
  /// 将 StructuredTextPage 扁平化为按 y0 排序的行列表，缓存复用
  static List<FlatLine> flattenPage(StructuredTextPage page) {
    final lines = <FlatLine>[];
    for (int bi = 0; bi < page.blocks.length; bi++) {
      final block = page.blocks[bi];
      for (int li = 0; li < block.lines.length; li++) {
        final line = block.lines[li];
        final chars = <FlatChar>[];
        for (int ci = 0; ci < line.chars.length; ci++) {
          final c = line.chars[ci];
          chars.add(FlatChar(
            blockIndex: bi,
            lineIndex: li,
            charIndex: ci,
            x0: c.bbox.x0,
            y0: c.bbox.y0,
            x1: c.bbox.x1,
            y1: c.bbox.y1,
            character: c.character,
          ));
        }
        lines.add(FlatLine(
          blockIndex: bi,
          lineIndex: li,
          x0: line.bbox.x0,
          x1: line.bbox.x1,
          y0: line.bbox.y0,
          y1: line.bbox.y1,
          chars: chars,
        ));
      }
    }
    // MuPDF 已按阅读顺序输出，但显式按 y0 排序以防万一
    lines.sort((a, b) => a.y0.compareTo(b.y0));
    return lines;
  }
  
  /// 二分查找包含 [pdfY] 的行，结合 [pdfX] 消歧义（多栏/多块），未命中则返回最近行。
  static int findLineIndex(List<FlatLine> lines, double pdfX, double pdfY) {
    if (lines.isEmpty) return 0;

    int lo = 0, hi = lines.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (lines[mid].y0 < pdfY) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }

    // 二分查找后只需检查 lo 和 lo-1，同 Y 展开由 _collectSameYRange 完成
    if (lo < lines.length && lines[lo].y0 <= pdfY && pdfY <= lines[lo].y1) {
      
      final candidates = _collectSameYRange(lines, lo, pdfY);
      return _pickBestByX(lines, candidates, pdfX);
    }
    if (lo > 0 && lines[lo - 1].y0 <= pdfY && pdfY <= lines[lo - 1].y1) {
      final candidates = _collectSameYRange(lines, lo - 1, pdfY);
      return _pickBestByX(lines, candidates, pdfX);
    }
    // print(" No exact Y match for pdfY=$pdfY, candidates are lo=$lo and lo-1=${lo - 1}");
    // 无精确 Y 匹配 — 最近行，同时考虑同 y0 的其他 block 行
    if (lo >= lines.length) return lines.length - 1;
    final candidates = <int>[];
    if (lo < lines.length) candidates.add(lo);
    if (lo > 0) candidates.add(lo - 1);
    // 展开同 y0 的行（不同 block 可能在同一行）
    for (final c in candidates.toList()) {
      for (int i = c + 1; i < lines.length && lines[i].y0 == lines[c].y0; i++) {
        candidates.add(i);
      }
      for (int i = c - 1; i >= 0 && lines[i].y0 == lines[c].y0; i--) {
        candidates.add(i);
      }
    }
    return _pickBestByX(lines, candidates, pdfX);
  }

  /// 收集与 lines[idx] 相同 Y 范围（y0..y1 重叠）的所有行
  static List<int> _collectSameYRange(List<FlatLine> lines, int idx, double pdfY) {
    final result = <int>[idx];
    // 向前找同 Y 范围的行
    for (int i = idx + 1; i < lines.length; i++) {
      if (lines[i].y0 <= pdfY && pdfY <= lines[i].y1) {
        result.add(i);
      } else if (lines[i].y0 > pdfY) {
        break;
      }
    }
    // 向后找
    for (int i = idx - 1; i >= 0; i--) {
      if (lines[i].y0 <= pdfY && pdfY <= lines[i].y1) {
        result.add(i);
      } else if (lines[i].y1 < pdfY) {
        break;
      }
    }
    return result;
  }

  /// 在候选行中选择 X 距离最近的行
  static int _pickBestByX(List<FlatLine> lines, List<int> indices, double pdfX) {
    int best = indices.first;
    double bestDist = _horizontalDist(lines[best], pdfX);
    for (int j = 1; j < indices.length; j++) {
      final d = _horizontalDist(lines[indices[j]], pdfX);
      if (d < bestDist) {
        bestDist = d;
        best = indices[j];
      }
    }
    return best;
  }

  /// 判断 pdfX 是否在行的水平范围 [x0, x1] 内
  static bool isPointInLineXRange(FlatLine line, double pdfX) {
    return pdfX >= line.x0 && pdfX <= line.x1;
  }

  /// pdfX 到行水平范围的距离：在范围内为 0，否则为到最近边界的距离
  static double _horizontalDist(FlatLine line, double pdfX) {
    if (pdfX < line.x0) return line.x0 - pdfX;
    if (pdfX > line.x1) return pdfX - line.x1;
    return 0;
  }

  /// 二分查找行内最接近 [pdfX] 的字符。O(log M)
  static int findCharInLine(FlatLine line, double pdfX) {
    final chars = line.chars;
    if (chars.isEmpty) return 0;

    int lo = 0, hi = chars.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (chars[mid].x1 < pdfX) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }

    if (lo >= chars.length) return chars.length - 1;
    if (chars[lo].x0 <= pdfX && pdfX <= chars[lo].x1) return lo;

    if (lo > 0) {
      final distToLo = (chars[lo].x0 - pdfX).abs();
      final distToPrev = (pdfX - chars[lo - 1].x1).abs();
      return distToLo <= distToPrev ? lo : lo - 1;
    }
    return lo;
  }

  /// 给定 PDF 坐标，返回最近的字符位置
  static CharPosition findNearestChar(
    List<FlatLine> lines,
    double pdfX,
    double pdfY,
  ) {
    final lineIdx = findLineIndex(lines, pdfX, pdfY);
    final line = lines[lineIdx];
    final charIdx = findCharInLine(line, pdfX);
    return CharPosition(
      blockIndex: line.blockIndex,
      lineIndex: line.lineIndex,
      charIndex: charIdx,
    );
  }

  /// 在已排序的 FlatLine 列表中查找匹配 [blockIndex] 和 [lineIndex] 的索引
  static int findFlatLineIndex(List<FlatLine> lines, int blockIndex, int lineIndex) {
    for (int i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.blockIndex == blockIndex && l.lineIndex == lineIndex) return i;
    }
    return -1;
  }

  /// Widget 逻辑像素 → PDF 坐标
  static double widgetToPdf(double widgetCoord, double dpr, double scale) {
    return widgetCoord * dpr / scale;
  }

  /// PDF 坐标 → Widget 逻辑像素
  static double pdfToWidget(double pdfCoord, double dpr, double scale) {
    return pdfCoord * scale / dpr;
  }
}
