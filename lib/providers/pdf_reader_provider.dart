import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:unified_pdf_reader/mupdf/mupdf.dart';

/// PDF 阅读器状态
class PdfReaderState {
  final String? filePath;
  final String? fileHash;
  final int currentPage;
  final int totalPages;
  final String? errorMessage;
  final double globalScale;
  final bool isCtrlPressed;
  final Map<int, double> pageOriginalHeights;
  // final Map<int, double> accumulatedPageHeights;
  final Map<String, Map<int, List<int>>> docRawPageSizes;
  final SendPort? pdfSendPort;
  final bool isPageIndicatorVisible;
  final int displayedPage;
  final Map<int, ui.Image> pageImages;
  final Map<int, ui.Image> highResPageImages;
  final double viewportWidth;
  final bool isHorizontalMode;
  final int originalMaxWidth;
  final bool isLoading;

  const PdfReaderState({
    this.filePath,
    this.fileHash,
    this.currentPage = 0,
    this.totalPages = 0,
    this.errorMessage,
    this.globalScale = 1.0,
    this.isCtrlPressed = false,
    this.pageOriginalHeights = const {},
    // this.accumulatedPageHeights = const {},
    this.docRawPageSizes = const {},
    this.pdfSendPort,
    this.isPageIndicatorVisible = true,
    this.displayedPage = 1,
    this.pageImages = const {},
    this.highResPageImages = const {},
    this.viewportWidth = 0.0,
    this.isHorizontalMode = false,
    this.originalMaxWidth = 0,
    this.isLoading = false,
  });

  PdfReaderState copyWith({
    String? filePath,
    String? fileHash,
    int? currentPage,
    int? totalPages,
    String? errorMessage,
    double? globalScale,
    bool? isCtrlPressed,
    Map<int, double>? pageOriginalHeights,
    // Map<int, double>? accumulatedPageHeights,
    Map<String, Map<int, List<int>>>? docRawPageSizes,
    SendPort? pdfSendPort,
    bool? isPageIndicatorVisible,
    int? displayedPage,
    Map<int, ui.Image>? pageImages,
    Map<int, ui.Image>? highResPageImages,
    double? viewportWidth,
    bool? isHorizontalMode,
    bool clearFilePath = false,
    bool clearErrorMessage = false,
    int? originalMaxWidth,
    bool? isLoading,
  }) {
    return PdfReaderState(
      filePath: clearFilePath ? null : (filePath ?? this.filePath),
      fileHash: fileHash ?? this.fileHash,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      globalScale: globalScale ?? this.globalScale,
      isCtrlPressed: isCtrlPressed ?? this.isCtrlPressed,
      pageOriginalHeights: pageOriginalHeights ?? this.pageOriginalHeights,
      docRawPageSizes:
          docRawPageSizes ?? this.docRawPageSizes,
      pdfSendPort: pdfSendPort ?? this.pdfSendPort,
      isPageIndicatorVisible:
          isPageIndicatorVisible ?? this.isPageIndicatorVisible,
      displayedPage: displayedPage ?? this.displayedPage,
      pageImages: pageImages ?? this.pageImages,
      highResPageImages: highResPageImages ?? this.highResPageImages,
      viewportWidth: viewportWidth ?? this.viewportWidth,
      isHorizontalMode: isHorizontalMode ?? this.isHorizontalMode,
      originalMaxWidth: originalMaxWidth ?? this.originalMaxWidth,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// PDF 阅读器 Notifier
class PdfReaderNotifier extends Notifier<PdfReaderState> {
  Isolate? _pdfIsolate;
  ReceivePort? _pdfReceivePort;
  SendPort? _pdfSendPort;

  double _oldScale = 1.0;
  double _scrollOffset = 0.0;
  double _mouseY = 0.0;
  double _mouseX = 0.0;
  double _horizontalScrollOffset = 0.0;

  List<double> _detectionLineHeights = [];

  Timer? _hideIndicatorTimer;
  Timer? _highResDebounceTimer;

  final Set<int> _renderingHighResPages = <int>{};

  static const double _separatorHeight = 10.0;
  static const double _highResScaleFactor = 5.0;
  static const double _verticalPadding = 5.0;

  /// 高清晰度渲染窗口半径：当前页前后各几页
  static const int _highResWindowRadius = 3;

  final GlobalKey listViewKey = GlobalKey();

  @override
  PdfReaderState build() {
    return const PdfReaderState();
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _hideIndicatorTimer?.cancel();
    _highResDebounceTimer?.cancel();
    _closePdf();
  }

  void initialize() {
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  /// 计算检测线位置的实际高度
  void calculateDetectionLineHeights(
    double ratio,
    // Map<int, double> pageHeights,
  ) {
    final result = <double>[];
    // final accumulatedHeights = Map.of(state.accumulatedPageHeights);

    double totalHeight = _verticalPadding;
    double detectionLineHeight = totalHeight;
    final residualRatio = 1 - ratio;
    final scale = state.globalScale;

    for (int i = 0; i < state.totalPages; i++) {
      final scaledHeight = (state.pageOriginalHeights[i] ?? 0.0) * scale;
      totalHeight += scaledHeight;

      detectionLineHeight = totalHeight - residualRatio * scaledHeight;
      result.add(detectionLineHeight);

      totalHeight += _separatorHeight;
      // accumulatedHeights[i] = totalHeight;
    }

    _detectionLineHeights = result;

    // state = state.copyWith(accumulatedPageHeights: accumulatedHeights);
  }

  bool _handleKeyEvent(KeyEvent event) {
    final isCtrl = HardwareKeyboard.instance.logicalKeysPressed.any(
      (key) =>
          key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight ||
          key == LogicalKeyboardKey.metaLeft ||
          key == LogicalKeyboardKey.metaRight,
    );

    if (state.isCtrlPressed != isCtrl) {
      onCtrlPressed(isCtrl);
    }
    return false;
  }

  // Future<void> renderPage(
  //   int pageIndex,
  //   double scale,
  //   double devicePixelRatio,
  // ) async {
  //   final renderScale = scale * devicePixelRatio;
  //   final result = await _renderPage(pageIndex, scale: renderScale);

  //   if (result != null && result['success']) {
  //     ui.decodeImageFromPixels(
  //       result['data'],
  //       result['width'],
  //       result['height'],
  //       ui.PixelFormat.rgba8888,
  //       (img) {
  //         final newPageImages = Map<int, ui.Image>.of(state.pageImages);
  //         newPageImages[pageIndex] = img;
  //         state = state.copyWith(pageImages: newPageImages);
  //       },
  //     );
  //   }
  // }

  // Future<void> renderAllPages(double devicePixelRatio) async {
  //   final newPageImages = Map<int, ui.Image>.of(state.pageImages);
  //   if (newPageImages.isNotEmpty) {
  //     for (final image in newPageImages.values) {
  //       image.dispose();
  //     }
  //     newPageImages.clear();
  //   }

  //   for (int i = 0; i < state.totalPages; i++) {
  //     final result = await _renderPage(i, scale: 1.0 * devicePixelRatio);
  //     if (result != null && result['success']) {
  //       ui.decodeImageFromPixels(
  //         result['data'],
  //         result['width'],
  //         result['height'],
  //         ui.PixelFormat.rgba8888,
  //         (img) {
  //           newPageImages[i] = img;
  //         },
  //       );
  //     }
  //   }
  //   state = state.copyWith(pageImages: newPageImages, isLoading: false);
  // }

  Future<void> onScrollChanged(
    ScrollController scrollController,
    double devicePixelRatio,
  ) async {
    if (state.totalPages == 0 || !scrollController.hasClients) return;
    if (_detectionLineHeights.isEmpty) return;

    final scrollOffset = scrollController.offset;
    int newPage = 0;
    final startIndex = (state.currentPage - 1).clamp(
      0,
      _detectionLineHeights.length,
    );

    for (int i = startIndex; i < _detectionLineHeights.length - 1; i++) {
      if (scrollOffset >= _detectionLineHeights[i] &&
          scrollOffset < _detectionLineHeights[i + 1]) {
        newPage = i + 1;
        break;
      }
    }

    newPage = newPage.clamp(0, state.totalPages - 1);

    if (newPage != state.currentPage) {
      state = state.copyWith(currentPage: newPage);
      showPageIndicator();
      _highResDebounceTimer?.cancel();
      _highResDebounceTimer = Timer(const Duration(milliseconds: 100), () {
        _updateHighResCache(devicePixelRatio);
      });
    }
  }

  Future<ui.Image?> _decodeImageFromPixels(
    Uint8List data,
    int width,
    int height,
  ) {
    final completer = Completer<ui.Image?>();
    ui.decodeImageFromPixels(
      data,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (img) => completer.complete(img),
    );
    return completer.future;
  }

  Future<void> _updateHighResCache(double devicePixelRatio) async {
    // print("object");
    if (state.totalPages == 0) return;

    final int start = (state.currentPage - _highResWindowRadius).clamp(
      0,
      state.totalPages - 1,
    );
    final int end = (state.currentPage + _highResWindowRadius).clamp(
      0,
      state.totalPages - 1,
    );
    final targetPages = {for (int i = start; i <= end; i++) i};

    // Remove pages outside the window
    final toRemove = state.highResPageImages.keys
        .where((k) => !targetPages.contains(k))
        .toList();

    // Add pages inside the window that are not yet cached or rendering
    // Sort by distance from current page so nearby pages render first
    final toAdd = targetPages
        .where(
          (p) =>
              !state.highResPageImages.containsKey(p) &&
              !_renderingHighResPages.contains(p),
        )
        .toList()
      ..sort((a, b) => (a - state.currentPage).abs().compareTo(
            (b - state.currentPage).abs(),
          ));
    // print(toAdd);
    for (final pageIndex in toAdd) {
      _renderingHighResPages.add(pageIndex);
      final renderScale = _highResScaleFactor * devicePixelRatio;

      // print("awaiting render of page $pageIndex with scale $renderScale");
      final result = await _renderPage(pageIndex, scale: renderScale);
      // print("render result for page $pageIndex: $result");
      if (result != null && result['success']) {
        final img = await _decodeImageFromPixels(
          result['data'],
          result['width'],
          result['height'],
        );
        // _renderingHighResPages.remove(pageIndex);
        if (img != null) {
          final newHighRes = Map<int, ui.Image>.of(state.highResPageImages);
          newHighRes[pageIndex] = img;
          state = state.copyWith(highResPageImages: newHighRes);
        }
      } else {
        _renderingHighResPages.remove(pageIndex);
      }
    }
    // print(_renderingHighResPages);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (toRemove.isNotEmpty) {
        final newHighRes = Map<int, ui.Image>.of(state.highResPageImages);
        for (final idx in toRemove) {
          newHighRes[idx]?.dispose();
          newHighRes.remove(idx);
        }
        state = state.copyWith(highResPageImages: newHighRes);
      }
    });
  }

  void handlePointerSignal(
    PointerSignalEvent event,
    ScrollController scrollController, {
    ScrollController? horizontalScrollController,
  }) {
    if (event is PointerScrollEvent && state.isCtrlPressed) {
      final double scrollDelta = event.scrollDelta.dy;
      if (scrollDelta == 0) return;

      final double scaleChange = scrollDelta < 0 ? 0.2 : -0.2;
      final double targetScale = (state.globalScale + scaleChange).clamp(
        0.5,
        8.0,
      );
      if (scrollController.hasClients) {
        _oldScale = state.globalScale;
        _scrollOffset = scrollController.offset;
        _mouseY = event.localPosition.dy;
      }
      if (horizontalScrollController?.hasClients ?? false) {
        _mouseX = event.localPosition.dx;
        _horizontalScrollOffset = horizontalScrollController!.offset;
      }

      onScaleChanged(targetScale, scrollController, horizontalScrollController);
    } else {
      if (scrollController.hasClients) {
        _scrollOffset = scrollController.offset;
        _mouseY = event.localPosition.dy;
      }
      if (horizontalScrollController?.hasClients ?? false) {
        _mouseX = event.localPosition.dx;
        _horizontalScrollOffset = horizontalScrollController!.offset;
      }
    }
  }

  void onScaleChanged(
    double newScale,
    ScrollController scrollController, [
    ScrollController? horizontalScrollController,
  ]) {
    state = state.copyWith(globalScale: newScale);
    onPageSizeMeasured();
    restoreScrollAfterScale(scrollController);
    restoreHorizontalScrollAfterScale(horizontalScrollController);
  }

  void onCtrlPressed(bool isCtrlPressed) {
    if (state.isCtrlPressed != isCtrlPressed) {
      state = state.copyWith(isCtrlPressed: isCtrlPressed);
    }
  }

  void onPageSizeMeasured() {
    calculateDetectionLineHeights(0.75);
  }

  void onViewportWidthChanged(double viewportWidth, double screenWidth) {
    final shouldBeHorizontal = viewportWidth >= screenWidth;
    // print('screenWidth: $screenWidth, viewportWidth: $viewportWidth, shouldBeHorizontal: $shouldBeHorizontal');
    state = state.copyWith(
      viewportWidth: viewportWidth,
      isHorizontalMode: shouldBeHorizontal,
    );
  }

  void restoreScrollAfterScale(ScrollController scrollController) {
    if (!scrollController.hasClients) return;

    const double topPadding = 5.0;
    const double separatorHeight = 10.0;

    final double gapsHeightAboveCursor =
        topPadding + ((state.currentPage) * (separatorHeight));

    final double pureContentYOld =
        (_scrollOffset + _mouseY) - gapsHeightAboveCursor;

    final double ratio = state.globalScale / _oldScale;
    final double pureContentYNew = pureContentYOld * ratio;

    final double newOffset =
        (pureContentYNew + gapsHeightAboveCursor) - _mouseY;

    if (newOffset <= 0) {
      scrollController.jumpTo(0);
      return;
    }

    final clampedOffset = newOffset.clamp(
      scrollController.position.minScrollExtent,
      scrollController.position.maxScrollExtent,
    );

    scrollController.jumpTo(clampedOffset);
  }

  void restoreHorizontalScrollAfterScale(
    ScrollController? horizontalScrollController,
  ) {
    if (horizontalScrollController == null ||
        !horizontalScrollController.hasClients) {
      return;
    }
    // print("object");
    final double ratio = state.globalScale / _oldScale;
    final double contentXOld = _horizontalScrollOffset + _mouseX;
    final double contentXNew = contentXOld * ratio;
    final double newOffset = contentXNew - _mouseX;

    final clampedOffset = newOffset.clamp(
      horizontalScrollController.position.minScrollExtent,
      horizontalScrollController.position.maxScrollExtent,
    );
    // print(clampedOffset);
    horizontalScrollController.jumpTo(clampedOffset);
  }

  Future<void> pickPdf(double devicePixelRatio) async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(type: FileType.any);
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        if (!path.toLowerCase().endsWith('.pdf')) {
          state = state.copyWith(errorMessage: '请选择 PDF 文件');
          return;
        }

        // state = state.copyWith(errorMessage: null);
        // print(doc.pageCount);
        await _initPdfIsolate(path, devicePixelRatio);
        // await renderAllPages(devicePixelRatio);

        // state = state.copyWith(errorMessage: null);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: '选择文件失败：$e');
    }
  }

  // @override
  // set state(PdfReaderState newState) {
  //   // TODO: implement state

  //   print(
  //     'State org:  ${state.fileHash}}',
  //   );

  //   super.state = newState;
  //   print(
  //     'State set: ${state.fileHash}}',
  //   );
  // }

  Future<void> _initPdfIsolate(String path, double devicePixelRatio) async {
    // state = state.copyWith(clearErrorMessage: true);

    try {
      _closePdf();
      _pdfReceivePort = ReceivePort();
      _pdfIsolate = await Isolate.spawn(
        _pdfIsolateEntry,
        _pdfReceivePort!.sendPort,
      );

      state = state.copyWith(isLoading: true);

      final List<dynamic> initData = await _pdfReceivePort!.first;
      _pdfSendPort = initData[0] as SendPort;

      final bytes = await File(path).readAsBytes();
      final fileHash = md5.convert(bytes).toString();
      final responsePort = ReceivePort();
      _pdfSendPort!.send({
        'type': 'init',
        'path': path,
        // 'fileHash': fileHash,
        'replyPort': responsePort.sendPort,
      });

      final initResult = await responsePort.first;
      responsePort.close();

      if (initResult['success']) {
        final pageOriginalSizes =
            initResult['pageOriginalSizes'] as Map<int, List<int>>? ?? {};

        final int originalMaxWidth = initResult['originalMaxWidth'] ?? 0;

        final Map<String, Map<int, List<int>>> pageRawSizesCache = {
          fileHash: pageOriginalSizes,
        };

        final renderedPixedMap =
            initResult['renderedPixedMap'] as Map<int, Uint8List>? ?? {};
        // print(renderedPixedMap);
        final pageImages = <int, ui.Image>{};

        for (final entry in renderedPixedMap.entries) {
          final pageIndex = entry.key;
          final data = entry.value;
          final pageSize = pageOriginalSizes[pageIndex];
          if (pageSize != null) {
            final img = await _decodeImageFromPixels(
              data,
              pageSize[0],
              pageSize[1],
            );
            if (img != null) {
              pageImages[pageIndex] = img;
            }
          }
        }
        final pageHeights = Map.of(state.pageOriginalHeights);

        for (int i = 0; i < initResult['pageCount']; i++) {
          pageHeights[i] =
              (pageOriginalSizes[i]?[1].toDouble() ?? 0.0) / devicePixelRatio;
          //   originalMaxWidth =
          //       max(originalMaxWidth, pageOriginalSizes[i]?[0] ?? 0.0);
        }

        // print(pageImages.length);
        state = state.copyWith(
          filePath: path,
          fileHash: fileHash,
          totalPages: initResult['pageCount'],
          pdfSendPort: _pdfSendPort,
          docRawPageSizes: pageRawSizesCache,
          pageOriginalHeights: pageHeights,
          pageImages: pageImages,
          originalMaxWidth: originalMaxWidth,
          isLoading: false,
        );

        calculateDetectionLineHeights(0.75);

        // print('PDF 初始化成功，页数：${state.totalPages}，原始最大宽度：${state.originalMaxWidth}');
        await _updateHighResCache(devicePixelRatio);
        // print('PDF 初始化成功，页数：${state.totalPages}，原始最大宽度：${state.originalMaxWidth}');
        // print(" PDF 页面渲染完成");
      } else {
        state = state.copyWith(errorMessage: initResult['error'] as String);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: '加载 PDF 异常：$e');
    }
  }

  void clearError() {
    state = state.copyWith(clearErrorMessage: true);
  }

  void closePdf() {
    _closePdf();
    state = const PdfReaderState();
  }

  void showPageIndicator() {
    _hideIndicatorTimer?.cancel();
    state = state.copyWith(
      isPageIndicatorVisible: true,
      displayedPage: state.currentPage + 1,
    );
    _hideIndicatorTimer = Timer(const Duration(seconds: 2), () {
      hidePageIndicator();
    });
  }

  void hidePageIndicator() {
    state = state.copyWith(isPageIndicatorVisible: false);
  }

  void _closePdf() {
    if (state.fileHash == null) return;
    _pdfReceivePort?.close();
    _pdfIsolate?.kill(priority: Isolate.immediate);
    _pdfIsolate = null;
    _pdfSendPort = null;

    for (final image in state.pageImages.values) {
      image.dispose();
    }
    for (final image in state.highResPageImages.values) {
      image.dispose();
    }
    _renderingHighResPages.clear();
    state = state.copyWith(
      pageImages: {},
      highResPageImages: {},
      totalPages: 0,
    );
  }

  Future<Map<String, dynamic>?> _renderPage(
    int pageIndex, {
    double scale = 1.0,
  }) async {
    if (_pdfSendPort == null) return null;
    final responsePort = ReceivePort();
    _pdfSendPort!.send({
      'type': 'render',
      'pageIndex': pageIndex,
      'scale': scale,
      'replyPort': responsePort.sendPort,
    });
    final result = await responsePort.first;
    responsePort.close();
    return result as Map<String, dynamic>?;
  }

  static void _pdfIsolateEntry(SendPort mainSendPort) {
    final childReceivePort = ReceivePort();
    mainSendPort.send([childReceivePort.sendPort]);

    // pdfiumBindings.FPDF_InitLibrary();
    // FPDF_DOCUMENT? doc;

    Map<int, List<int>>? pageOriginalSizes;
    final doc = PdfDocument();

    childReceivePort.listen((message) {
      final String type = message['type'];
      final SendPort replyPort = message['replyPort'];

      if (type == 'init') {
        final Map<int, Uint8List> renderedPixedMap = {};
        // final Uint8List bytes = message['pdfBytes'];
        final path = message['path'] as String;
        int originalMaxWidth = 0;
        if (doc.isOpen) doc.dispose();

        doc.open(path);

        final pageCount = doc.pageCount;
        pageOriginalSizes = <int, List<int>>{};

        for (int i = 0; i < pageCount; i++) {
          final page = doc.renderPage(
            pageNumber: i,
            zoom: 100.0,
            rotate: 0.0,
            includeAlpha: false,
          );

          pageOriginalSizes![i] = [page.width, page.height];

          originalMaxWidth = max(
            originalMaxWidth,
            pageOriginalSizes![i]?[0] ?? 0,
          );
          renderedPixedMap[i] = page.pixels;
        }
        replyPort.send({
          'success': true,
          'pageCount': pageCount,
          'pageOriginalSizes': pageOriginalSizes,
          'originalMaxWidth': originalMaxWidth,
          'renderedPixedMap': renderedPixedMap,
        });
      } else if (type == 'render') {
        if (pageOriginalSizes == null) return;

        final int index = message['pageIndex'];
        final double scale = (message['scale'] ?? 1.0);

        final bitmap = doc.renderPage(
          pageNumber: index,
          zoom: scale * 100,
          rotate: 0.0,
          includeAlpha: false,
        );

        final rawBytes = bitmap.pixels;

        // final u32list = rawBytes.buffer.asUint32List();
        // for (int i = 0; i < u32list.length; i++) {
        //   final u32 = u32list[i];
        //   u32list[i] =
        //       (u32 & 0xFF00FF00) |
        //       ((u32 & 0x00FF0000) >> 16) |
        //       ((u32 & 0x000000FF) << 16);
        // }

        replyPort.send({
          'success': true,
          'data': Uint8List.fromList(rawBytes),
          'width': bitmap.width,
          'height': bitmap.height,
        });

        // bitmap

        // pdfiumBindings.FPDFBitmap_Destroy(bitmap);
        // pdfiumBindings.FPDF_ClosePage(page);
      }
    });
  }
}

final pdfReaderProvider = NotifierProvider<PdfReaderNotifier, PdfReaderState>(
  PdfReaderNotifier.new,
);
