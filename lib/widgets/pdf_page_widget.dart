import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/pdf_reader_provider.dart';
import '../mupdf/mupdf.dart';
import '../utils/text_selection.dart';
import 'highlight_painter.dart';
import 'selection_highlight_painter.dart';

class PdfPageWidget extends HookConsumerWidget {
  final int pageIndex;

  const PdfPageWidget({super.key, required this.pageIndex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicePixelRatio = View.of(context).devicePixelRatio;

    final activeTabId = ref.watch(
      workspaceProvider.select((s) => s.activeTabId),
    );

    final pageSizes = activeTabId != null
        ? ref.watch(
            pdfReaderProvider(activeTabId).select(
              (state) => state.docRawPageSizes[state.fileHash]?[pageIndex],
            ),
          )
        : null;
    final originalWidth = pageSizes?[0] ?? 0;
    final originalHeight = pageSizes?[1] ?? 0;

    final pageImage = activeTabId != null
        ? ref.watch(
            pdfReaderProvider(activeTabId).select(
              (state) =>
                  state.highResPageImages[pageIndex] ??
                  state.pageImages[pageIndex],
            ),
          )
        : null;

    final scale = activeTabId != null
        ? ref.watch(
            pdfReaderProvider(activeTabId).select((state) => state.globalScale),
          )
        : 1.0;
    final selection = activeTabId != null
        ? ref.watch(
            pdfReaderProvider(
              activeTabId,
            ).select((state) => state.pageSelections[pageIndex]),
          )
        : null;

    final pageAnnotations = activeTabId != null
        ? ref.watch(
            pdfReaderProvider(
              activeTabId,
            ).select((state) => state.pageAnnotations[pageIndex]),
          )
        : null;

    final annotationHighlightRects = useMemoized(() {
      if (pageAnnotations == null) return <Rect>[];
      return pageAnnotations
          .where((a) => a.type == 8) // PDF_ANNOT_HIGHLIGHT
          .map(
            (a) => Rect.fromLTRB(
              TextSelectionAlgorithm.pdfToWidget(
                a.rect.x0,
                devicePixelRatio,
                scale,
              ),
              TextSelectionAlgorithm.pdfToWidget(
                a.rect.y0,
                devicePixelRatio,
                scale,
              ),
              TextSelectionAlgorithm.pdfToWidget(
                a.rect.x1,
                devicePixelRatio,
                scale,
              ),
              TextSelectionAlgorithm.pdfToWidget(
                a.rect.y1,
                devicePixelRatio,
                scale,
              ),
            ),
          )
          .toList();
    }, [pageAnnotations, scale, devicePixelRatio]);

    final isHoveringText = useState(true);

    return _buildPageContent(
      context,
      ref,
      originalWidth,
      originalHeight,
      scale,
      devicePixelRatio,
      pageImage,
      selection,
      annotationHighlightRects,
      isHoveringText,
    );
  }

  Widget _buildPageContent(
    BuildContext context,
    WidgetRef ref,
    int originalWidth,
    int originalHeight,
    double scale,
    double devicePixelRatio,
    Uint8List? pageImage,
    PageTextSelection? selection,
    List<Rect> annotationHighlightRects,
    ValueNotifier<bool> isHoveringText,
  ) {
    if (originalWidth == 0 || originalHeight == 0) {
      return Center(
        child: Container(
          width: 595 / devicePixelRatio * scale,
          height: 842 / devicePixelRatio * scale,
          color: Colors.white,
        ),
      );
    }

    final pageWidth = originalWidth / devicePixelRatio * scale;
    final pageHeight = originalHeight / devicePixelRatio * scale;

    Widget pageContent = RepaintBoundary(
      child: SizedBox(
        width: pageWidth,
        height: pageHeight,
        child: Container(
          color: Colors.white,

          child: Stack(
            children: [
              if (pageImage != null)
                // Positioned.fill(
                // child:
                Image.memory(
                  pageImage,
                  width: pageWidth,
                  height: pageHeight,
                  fit: BoxFit.contain,
                  isAntiAlias: true,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                ),
              // ),
              if (annotationHighlightRects.isNotEmpty)
                CustomPaint(
                  painter: HighlightPainter(rects: annotationHighlightRects),
                ),
              if (selection != null && selection.highlightRects.isNotEmpty)
                _buildSelectionHighlight(selection, scale),
            ],
          ),
        ),
      ),
    );

    final activeTabId = ref.read(
      workspaceProvider.select((s) => s.activeTabId),
    );
    return Center(
      child: MouseRegion(
        cursor: isHoveringText.value
            ? SystemMouseCursors.text
            : SystemMouseCursors.basic,
        onHover: (event) {
          if (activeTabId == null) {
            isHoveringText.value = false;
            return;
          }
          final notifier = ref.read(pdfReaderProvider(activeTabId).notifier);
          notifier.fetchStructuredText(pageIndex).then((stext) {
            if (stext == null) return;
            if (!context.mounted) return;
            _updateHoverState(
              stext,
              event.localPosition.dx,
              event.localPosition.dy,
              devicePixelRatio,
              scale,
              isHoveringText,
            );
            notifier.setHoverState(pageIndex, isHoveringText.value);
          });
        },
        child: pageContent,
      ),
    );
  }

  Widget _buildSelectionHighlight(
    PageTextSelection selection,
    double currentScale,
  ) {
    List<Rect> displayRects = selection.highlightRects;
    if (selection.scale != currentScale && selection.scale > 0) {
      final ratio = currentScale / selection.scale;
      displayRects = displayRects
          .map(
            (r) => Rect.fromLTRB(
              r.left * ratio,
              r.top * ratio,
              r.right * ratio,
              r.bottom * ratio,
            ),
          )
          .toList();
    }
    return CustomPaint(painter: SelectionHighlightPainter(rects: displayRects));
  }

  void _updateHoverState(
    StructuredTextPage stext,
    double localX,
    double localY,
    double dpr,
    double scale,
    ValueNotifier<bool> isHoveringText,
  ) {
    final lines = TextSelectionAlgorithm.flattenPage(stext);
    if (lines.isEmpty) {
      isHoveringText.value = false;
      return;
    }
    final pdfX = TextSelectionAlgorithm.widgetToPdf(localX, dpr, scale);
    final pdfY = TextSelectionAlgorithm.widgetToPdf(localY, dpr, scale);
    final lineIdx = TextSelectionAlgorithm.findLineIndex(lines, pdfX, pdfY);
    // print("Hover at localX=$localX, localY=$localY => pdfX=$pdfX, pdfY=$pdfY => lineIdx=$lineIdx");
    if (lineIdx == null) {
      isHoveringText.value = false;
      return;
    }
    final line = lines[lineIdx];
    isHoveringText.value =
        TextSelectionAlgorithm.isPointInLineXRange(line, pdfX) &&
        pdfY >= line.y0 &&
        pdfY <= line.y1;
  }
}
