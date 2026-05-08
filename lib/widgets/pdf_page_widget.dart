import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/pdf_reader_provider.dart';

class PdfPageWidget extends HookConsumerWidget {
  final int pageIndex;

  const PdfPageWidget({super.key, required this.pageIndex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicePixelRatio = View.of(context).devicePixelRatio;

    final activeTabId = ref.watch(workspaceProvider.select((s) => s.activeTabId));

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
                  state.highResPageImages[pageIndex] ?? state.pageImages[pageIndex],
            ),
          )
        : null;

    final scale = activeTabId != null
        ? ref.watch(
            pdfReaderProvider(activeTabId).select((state) => state.globalScale),
          )
        : 1.0;

    return _buildPageContent(
      originalWidth,
      originalHeight,
      scale,
      devicePixelRatio,
      pageImage,
    );
  }

  Widget _buildPageContent(
    int originalWidth,
    int originalHeight,
    double scale,
    double devicePixelRatio,
    ui.Image? pageImage,
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

    return SizedBox(
      width: originalWidth / devicePixelRatio * scale,
      height: originalHeight / devicePixelRatio * scale,
      child: FittedBox(
        fit: BoxFit.contain,
        child: pageImage == null
            ? SizedBox(
                width: originalWidth / devicePixelRatio * scale,
                height: originalHeight / devicePixelRatio * scale,
                child: const ColoredBox(color: Colors.white),
              )
            : RawImage(
                image: pageImage,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
      ),
    );
  }
}
