import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ffi' as ffi;
import 'dart:math';
import 'dart:ui' as ui;
import 'package:ffi/ffi.dart' as ffi_pkg;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart';

/// PDF 阅读器状态
class PdfReaderState {
  final String? filePath;
  final String? fileHash;
  final int currentPage;
  final int totalPages;
  final String? errorMessage;
  final double globalScale;
  final bool isCtrlPressed;
  final Map<int, double> pageHeights;
  final Map<String, Map<int, List<double>>> pageOriginalSizesCache;
  final SendPort? pdfSendPort;
  final bool isPageIndicatorVisible;
  final int displayedPage;
  final Map<int, ui.Image> pageImages;
  final Map<int, ui.Image> highResPageImages;
  final double viewportWidth;
  final bool isHorizontalMode;
  final double originalMaxWidth;

  const PdfReaderState({
    this.filePath,
    this.fileHash,
    this.currentPage = 0,
    this.totalPages = 0,
    this.errorMessage,
    this.globalScale = 1.0,
    this.isCtrlPressed = false,
    this.pageHeights = const {},
    this.pageOriginalSizesCache = const {},
    this.pdfSendPort,
    this.isPageIndicatorVisible = true,
    this.displayedPage = 1,
    this.pageImages = const {},
    this.highResPageImages = const {},
    this.viewportWidth = 0.0,
    this.isHorizontalMode = false,
    this.originalMaxWidth = 0.0,
  });

  PdfReaderState copyWith({
    String? filePath,
    String? fileHash,
    int? currentPage,
    int? totalPages,
    String? errorMessage,
    double? globalScale,
    bool? isCtrlPressed,
    Map<int, double>? pageHeights,
    Map<String, Map<int, List<double>>>? pageOriginalSizesCache,
    SendPort? pdfSendPort,
    bool? isPageIndicatorVisible,
    int? displayedPage,
    Map<int, ui.Image>? pageImages,
    Map<int, ui.Image>? highResPageImages,
    double? viewportWidth,
    bool? isHorizontalMode,
    bool clearFilePath = false,
    bool clearErrorMessage = false,
    double? originalMaxWidth,
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
      pageHeights: pageHeights ?? this.pageHeights,
      pageOriginalSizesCache:
          pageOriginalSizesCache ?? this.pageOriginalSizesCache,
      pdfSendPort: pdfSendPort ?? this.pdfSendPort,
      isPageIndicatorVisible:
          isPageIndicatorVisible ?? this.isPageIndicatorVisible,
      displayedPage: displayedPage ?? this.displayedPage,
      pageImages: pageImages ?? this.pageImages,
      highResPageImages: highResPageImages ?? this.highResPageImages,
      viewportWidth: viewportWidth ?? this.viewportWidth,
      isHorizontalMode: isHorizontalMode ?? this.isHorizontalMode,
      originalMaxWidth: originalMaxWidth ?? this.originalMaxWidth,
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

  List<double> _detectionLineHeights = [];

  Timer? _hideIndicatorTimer;

  final Set<int> _renderingHighResPages = <int>{};

  static const double _separatorHeight = 10.0;
  static const double _highResScaleFactor = 5.0;
  static const double _verticalPadding = 5.0;

  /// 高清晰度渲染窗口半径：当前页前后各几页
  static const int _highResWindowRadius = 5;

  final GlobalKey listViewKey = GlobalKey();

  @override
  PdfReaderState build() {
    return const PdfReaderState();
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _hideIndicatorTimer?.cancel();
    _closePdf();
  }

  void initialize() {
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  /// 计算检测线位置的实际高度
  void calculateDetectionLineHeights(
    double ratio,
    Map<int, double> pageHeights,
  ) {
    final result = <double>[];
    double totalHeight = _verticalPadding;
    double detectionLineHeight = totalHeight;
    final residualRatio = 1 - ratio;
    final scale = state.globalScale;
    for (int i = 0; i < state.totalPages; i++) {
      final scaledHeight = (pageHeights[i] ?? 0.0) * scale;
      totalHeight += scaledHeight;

      detectionLineHeight = totalHeight - residualRatio * scaledHeight;
      result.add(detectionLineHeight);

      totalHeight += _separatorHeight;
    }

    _detectionLineHeights = result;
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

  Future<void> renderPage(
    int pageIndex,
    double scale,
    double devicePixelRatio,
  ) async {
    final renderScale = scale * devicePixelRatio;
    final result = await _renderPage(pageIndex, scale: renderScale);

    if (result != null && result['success']) {
      ui.decodeImageFromPixels(
        result['data'],
        result['width'],
        result['height'],
        ui.PixelFormat.rgba8888,
        (img) {
          final newPageImages = Map<int, ui.Image>.of(state.pageImages);
          newPageImages[pageIndex] = img;
          state = state.copyWith(pageImages: newPageImages);
        },
      );
    }
  }

  Future<void> renderAllPages(double devicePixelRatio) async {
    final newPageImages = Map<int, ui.Image>.of(state.pageImages);
    newPageImages.clear();

    for (int i = 0; i < state.totalPages; i++) {
      final result = await _renderPage(i, scale: 1.0 * devicePixelRatio);
      if (result != null && result['success']) {
        ui.decodeImageFromPixels(
          result['data'],
          result['width'],
          result['height'],
          ui.PixelFormat.rgba8888,
          (img) {
            newPageImages[i] = img;
            state = state.copyWith(pageImages: newPageImages);
          },
        );
      }
    }
  }

  Future<void> onScrollChanged(
    ScrollController scrollController,
    double devicePixelRatio,
  ) async {
    if (state.totalPages == 0 || !scrollController.hasClients) return;
    if (_detectionLineHeights.isEmpty) return;

    final scrollOffset = scrollController.offset;
    int newPage = 0;

    for (int i = 0; i < _detectionLineHeights.length - 1; i++) {
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
      await _updateHighResCache(devicePixelRatio);
    }
  }

  Future<void> _updateHighResCache(double devicePixelRatio) async {
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

    if (toRemove.isNotEmpty) {
      final newHighRes = Map<int, ui.Image>.of(state.highResPageImages);
      for (final idx in toRemove) {
        newHighRes[idx]?.dispose();
        newHighRes.remove(idx);
      }
      state = state.copyWith(highResPageImages: newHighRes);
    }

    // Add pages inside the window that are not yet cached or rendering
    final toAdd = targetPages.where(
      (p) =>
          !state.highResPageImages.containsKey(p) &&
          !_renderingHighResPages.contains(p),
    );

    for (final pageIndex in toAdd) {
      _renderingHighResPages.add(pageIndex);
      final renderScale = _highResScaleFactor * devicePixelRatio;
      _renderPage(pageIndex, scale: renderScale).then((result) {
        if (result != null && result['success']) {
          ui.decodeImageFromPixels(
            result['data'],
            result['width'],
            result['height'],
            ui.PixelFormat.rgba8888,
            (img) {
              _renderingHighResPages.remove(pageIndex);
              final newHighRes = Map<int, ui.Image>.of(state.highResPageImages);
              newHighRes[pageIndex] = img;
              state = state.copyWith(highResPageImages: newHighRes);
            },
          );
        } else {
          _renderingHighResPages.remove(pageIndex);
        }
      });
    }
  }

  void handlePointerSignal(
    PointerSignalEvent event,
    ScrollController scrollController,
  ) {
    if (event is PointerScrollEvent && state.isCtrlPressed) {
      final double scrollDelta = event.scrollDelta.dy;
      if (scrollDelta == 0) return;

      final double scaleChange = scrollDelta < 0 ? 0.2 : -0.2;
      final double targetScale = (state.globalScale + scaleChange).clamp(
        0.5,
        6.0,
      );
      if (scrollController.hasClients) {
        _oldScale = state.globalScale;
        _scrollOffset = scrollController.offset;
        _mouseY = event.localPosition.dy;
      }

      onScaleChanged(targetScale, scrollController);
    } else {
      if (scrollController.hasClients) {
        _scrollOffset = scrollController.offset;
        _mouseY = event.localPosition.dy;
      }
    }
  }

  void onScaleChanged(double newScale, ScrollController scrollController) {
    state = state.copyWith(globalScale: newScale);
    restoreScrollAfterScale(scrollController);
    onPageSizeMeasured();
  }

  void onCtrlPressed(bool isCtrlPressed) {
    if (state.isCtrlPressed != isCtrlPressed) {
      state = state.copyWith(isCtrlPressed: isCtrlPressed);
    }
  }

  void onPageSizeMeasured() {
    calculateDetectionLineHeights(0.75, state.pageHeights);
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
        await _initPdfIsolate(path, devicePixelRatio);
        await renderAllPages(devicePixelRatio);
        state = state.copyWith(errorMessage: null);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: '选择文件失败：$e');
    }
  }

  Future<void> _initPdfIsolate(String path, double devicePixelRatio) async {
    state = state.copyWith(clearErrorMessage: true);

    try {
      _closePdf();
      _pdfReceivePort = ReceivePort();
      _pdfIsolate = await Isolate.spawn(
        _pdfIsolateEntry,
        _pdfReceivePort!.sendPort,
      );

      final List<dynamic> initData = await _pdfReceivePort!.first;
      _pdfSendPort = initData[0] as SendPort;

      final bytes = await File(path).readAsBytes();
      final fileHash = md5.convert(bytes).toString();
      final responsePort = ReceivePort();
      _pdfSendPort!.send({
        'type': 'init',
        'pdfBytes': bytes,
        'fileHash': fileHash,
        'replyPort': responsePort.sendPort,
      });

      final initResult = await responsePort.first;
      responsePort.close();

      if (initResult['success']) {
        final pageOriginalSizes =
            initResult['pageOriginalSizes'] as Map<int, List<double>>? ?? {};

        final double originalMaxWidth =
            initResult['originalMaxWidth'] as double? ?? 0.0;

        final Map<String, Map<int, List<double>>> pageOriginalSizesCache = {
          fileHash: pageOriginalSizes,
        };

        final pageHeights = Map.of(state.pageHeights);

        for (int i = 0; i < initResult['pageCount']; i++) {
          pageHeights[i] = (pageOriginalSizes[i]?[1] ?? 0.0) / devicePixelRatio;
          //   originalMaxWidth =
          //       max(originalMaxWidth, pageOriginalSizes[i]?[0] ?? 0.0);
        }
        state = state.copyWith(
          filePath: path,
          fileHash: fileHash,
          totalPages: initResult['pageCount'],
          pdfSendPort: _pdfSendPort,
          pageOriginalSizesCache: pageOriginalSizesCache,
          pageHeights: pageHeights,
          originalMaxWidth: originalMaxWidth,
        );
        calculateDetectionLineHeights(0.75, pageHeights);
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
    state = state.copyWith(pageImages: {}, highResPageImages: {});
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

    pdfiumBindings.FPDF_InitLibrary();
    FPDF_DOCUMENT? doc;
    ffi.Pointer<ffi.Uint8>? fileBuffer;
    Map<int, List<double>>? pageOriginalSizes;

    childReceivePort.listen((message) {
      final String type = message['type'];
      final SendPort replyPort = message['replyPort'];

      if (type == 'init') {
        final Uint8List bytes = message['pdfBytes'];
        double originalMaxWidth = 0.0;
        if (doc != null) pdfiumBindings.FPDF_CloseDocument(doc!);
        if (fileBuffer != null) ffi_pkg.calloc.free(fileBuffer!);

        fileBuffer = ffi_pkg.calloc<ffi.Uint8>(bytes.length);
        fileBuffer!.asTypedList(bytes.length).setAll(0, bytes);
        doc = pdfiumBindings.FPDF_LoadMemDocument(
          fileBuffer!.cast<ffi.Void>(),
          bytes.length,
          ffi.nullptr,
        );

        if (doc == ffi.nullptr) {
          replyPort.send({'success': false, 'error': 'PDF 载入失败'});
        } else {
          final pageCount = pdfiumBindings.FPDF_GetPageCount(doc!);
          pageOriginalSizes = <int, List<double>>{};
          for (int i = 0; i < pageCount; i++) {
            final page = pdfiumBindings.FPDF_LoadPage(doc!, i);
            pageOriginalSizes![i] = [
              pdfiumBindings.FPDF_GetPageWidthF(page),
              pdfiumBindings.FPDF_GetPageHeightF(page),
            ];

            originalMaxWidth = max(
              originalMaxWidth,
              pageOriginalSizes![i]?[0] ?? 0.0,
            );
            pdfiumBindings.FPDF_ClosePage(page);
          }
          replyPort.send({
            'success': true,
            'pageCount': pageCount,
            'pageOriginalSizes': pageOriginalSizes,
            'originalMaxWidth': originalMaxWidth,
          });
        }
      } else if (type == 'render') {
        if (doc == null || pageOriginalSizes == null) return;
        final int index = message['pageIndex'];
        final double scale = (message['scale'] ?? 1.0);
        final sizes = pageOriginalSizes!;

        final page = pdfiumBindings.FPDF_LoadPage(doc!, index);
        final pageSize = sizes[index];
        final double originalWidth = pageSize![0];
        final double originalHeight = pageSize[1];

        final int width = (originalWidth * scale).ceil();
        final int height = (originalHeight * scale).ceil();

        final bitmap = pdfiumBindings.FPDFBitmap_Create(width, height, 4);
        pdfiumBindings.FPDFBitmap_FillRect(
          bitmap,
          0,
          0,
          width,
          height,
          0xFFFFFFFF,
        );
        pdfiumBindings.FPDF_RenderPageBitmap(
          bitmap,
          page,
          0,
          0,
          width,
          height,
          0,
          FPDF_ANNOT | FPDF_LCD_TEXT,
        );

        final buffer = pdfiumBindings.FPDFBitmap_GetBuffer(bitmap);
        final stride = pdfiumBindings.FPDFBitmap_GetStride(bitmap);
        final rawBytes = buffer.cast<ffi.Uint8>().asTypedList(stride * height);

        final u32list = rawBytes.buffer.asUint32List();
        for (int i = 0; i < u32list.length; i++) {
          final u32 = u32list[i];
          u32list[i] =
              (u32 & 0xFF00FF00) |
              ((u32 & 0x00FF0000) >> 16) |
              ((u32 & 0x000000FF) << 16);
        }

        replyPort.send({
          'success': true,
          'data': Uint8List.fromList(rawBytes),
          'width': width,
          'height': height,
        });

        pdfiumBindings.FPDFBitmap_Destroy(bitmap);
        pdfiumBindings.FPDF_ClosePage(page);
      }
    });
  }
}

final pdfReaderProvider = NotifierProvider<PdfReaderNotifier, PdfReaderState>(
  PdfReaderNotifier.new,
);
