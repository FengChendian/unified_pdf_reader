import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/pdf_reader_provider.dart';
import '../utils/text_selection.dart';
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

    final isSelectionMode = activeTabId != null
        ? ref.watch(
            pdfReaderProvider(
              activeTabId,
            ).select((state) => state.isSelectionMode),
          )
        : false;

    final selection = activeTabId != null
        ? ref.watch(
            pdfReaderProvider(
              activeTabId,
            ).select((state) => state.pageSelections[pageIndex]),
          )
        : null;

    return _buildPageContent(
      context,
      ref,
      originalWidth,
      originalHeight,
      scale,
      devicePixelRatio,
      pageImage,
      isSelectionMode,
      selection,
    );
  }

  Widget _buildPageContent(
    BuildContext context,
    WidgetRef ref,
    int originalWidth,
    int originalHeight,
    double scale,
    double devicePixelRatio,
    ui.Image? pageImage,
    bool isSelectionMode,
    PageTextSelection? selection,
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
    // print(pageWidth);
    Widget pageContent = SizedBox(
      width: pageWidth,
      height: pageHeight,
      child: Stack(
        children: [
          // 底层：图片，现在填满 Stack 即可
          RawImage(
            image: pageImage,
            fit: BoxFit.fill, // 这里可以用 fill，因为父级 AspectRatio 已经限制了比例
            filterQuality: FilterQuality.medium,
          ),

          // 高亮层：现在的 (0,0) 正好就是图片的左上角
          if (selection != null && selection.highlightRects.isNotEmpty)
            _buildSelectionHighlight(selection, scale),
        ],
      ),
    );

    // Layer 1 (top): GestureDetector for text selection
    if (isSelectionMode) {
      final activeTabId = ref.read(
        workspaceProvider.select((s) => s.activeTabId),
      );
      return Center(
        child: MouseRegion(
          cursor: SystemMouseCursors.text,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              // print(details.localPosition);
              if (activeTabId == null) return;
              ref
                  .read(pdfReaderProvider(activeTabId).notifier)
                  .handleSelectionPanStart(
                    pageIndex,
                    details.localPosition,
                    devicePixelRatio,
                  );
            },
            onPanUpdate: (details) {
              if (activeTabId == null) return;
              ref
                  .read(pdfReaderProvider(activeTabId).notifier)
                  .handleSelectionPanUpdate(
                    pageIndex,
                    details.localPosition,
                    devicePixelRatio,
                  );
            },
            onPanEnd: (_) {
              if (activeTabId == null) return;
              ref
                  .read(pdfReaderProvider(activeTabId).notifier)
                  .handleSelectionPanEnd(pageIndex);
            },
            child: pageContent,
          ),
        ),
      );
    }

    return Center(child: pageContent);
  }

  Widget _buildSelectionHighlight(
    PageTextSelection selection,
    double currentScale,
  ) {
    List<HighlightRect> displayRects = selection.highlightRects;
    if (selection.scale != currentScale && selection.scale > 0) {
      final ratio = currentScale / selection.scale;
      displayRects = displayRects
          .map(
            (r) => HighlightRect(
              left: r.left * ratio,
              top: r.top * ratio,
              right: r.right * ratio,
              bottom: r.bottom * ratio,
            ),
          )
          .toList();
    }
    return CustomPaint(painter: SelectionHighlightPainter(rects: displayRects));
  }
}
