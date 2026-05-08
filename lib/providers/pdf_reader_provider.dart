import 'dart:async';
import 'dart:collection';
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
  final Map<int, double> accumulatedScaledPageHeights;
  final double maxScaledPageSumHeight;

  final Map<String, Map<int, List<int>>> docRawPageSizes;
  final SendPort? pdfSendPort;
  final bool isPageIndicatorVisible;
  final int displayedPage;
  final Map<int, ui.Image> pageImages;
  final Map<int, ui.Image> highResPageImages;
  final double viewportWidth;
  // final bool isHorizontalMode;
  final int originalPagesMaxWidth;
  final bool isLoading;
  final List<OutlineItem> outline;
  final bool isOutlinePanelOpen;
  final Set<String> expandedOutlineIds;

  const PdfReaderState({
    this.filePath,
    this.fileHash,
    this.currentPage = 0,
    this.totalPages = 0,
    this.errorMessage,
    this.globalScale = 1.0,
    this.isCtrlPressed = false,
    this.pageOriginalHeights = const {},
    this.accumulatedScaledPageHeights = const {},
    this.maxScaledPageSumHeight = 0.0,
    this.docRawPageSizes = const {},
    this.pdfSendPort,
    this.isPageIndicatorVisible = true,
    this.displayedPage = 1,
    this.pageImages = const {},
    this.highResPageImages = const {},
    this.viewportWidth = 0.0,
    this.originalPagesMaxWidth = 0,
    this.isLoading = false,
    this.outline = const [],
    this.isOutlinePanelOpen = false,
    this.expandedOutlineIds = const {},
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
    Map<int, double>? accumulatedScaledPageHeights,
    double? maxScaledPageSumHeight,
    Map<String, Map<int, List<int>>>? docRawPageSizes,
    SendPort? pdfSendPort,
    bool? isPageIndicatorVisible,
    int? displayedPage,
    Map<int, ui.Image>? pageImages,
    Map<int, ui.Image>? highResPageImages,
    double? viewportWidth,
    bool clearFilePath = false,
    bool clearErrorMessage = false,
    int? originalPagesMaxWidth,
    bool? isLoading,
    List<OutlineItem>? outline,
    bool? isOutlinePanelOpen,
    Set<String>? expandedOutlineIds,
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
      accumulatedScaledPageHeights:
          accumulatedScaledPageHeights ?? this.accumulatedScaledPageHeights,
      maxScaledPageSumHeight:
          maxScaledPageSumHeight ?? this.maxScaledPageSumHeight,
      docRawPageSizes: docRawPageSizes ?? this.docRawPageSizes,
      pdfSendPort: pdfSendPort ?? this.pdfSendPort,
      isPageIndicatorVisible:
          isPageIndicatorVisible ?? this.isPageIndicatorVisible,
      displayedPage: displayedPage ?? this.displayedPage,
      pageImages: pageImages ?? this.pageImages,
      highResPageImages: highResPageImages ?? this.highResPageImages,
      viewportWidth: viewportWidth ?? this.viewportWidth,
      originalPagesMaxWidth:
          originalPagesMaxWidth ?? this.originalPagesMaxWidth,
      isLoading: isLoading ?? this.isLoading,
      outline: outline ?? this.outline,
      isOutlinePanelOpen: isOutlinePanelOpen ?? this.isOutlinePanelOpen,
      expandedOutlineIds: expandedOutlineIds ?? this.expandedOutlineIds,
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
  Timer? _highResRenderTimer;

  final Queue<int> _highResRenderQueue = Queue<int>();
  bool _isRenderingHighRes = false;
  int? _currentlyRenderingPage;
  double _lastDevicePixelRatio = 1.0;

  static const double _separatorHeight = 10.0;
  static const double _highResScaleFactor = 5.0;
  // static const double _verticalPadding = 5.0;

  /// 高清晰度渲染窗口半径：当前页前后各几页
  static const int _highResWindowRadius = 2;

  /// 高清渲染队列轮询间隔
  static const Duration _highResRenderInterval = Duration(milliseconds: 100);

  // final GlobalKey listViewKey = GlobalKey();

  @override
  PdfReaderState build() {
    return const PdfReaderState();
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _hideIndicatorTimer?.cancel();
    _highResRenderTimer?.cancel();
    _closePdf();
  }

  void initialize() {
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _highResRenderTimer = Timer.periodic(
      _highResRenderInterval,
      (_) => _processHighResQueueTick(),
    );
  }

  /// 计算检测线位置的实际高度
  void calculateDetectionLineHeights(
    double ratio,
    // Map<int, double> pageHeights,
  ) {
    final result = <double>[];
    final accumulatedHeights = <int, double>{};

    double totalHeight = 0;
    double detectionLineHeight = totalHeight;
    final residualRatio = 1 - ratio;
    final scale = state.globalScale;

    for (int i = 0; i < state.totalPages; i++) {
      accumulatedHeights[i] = totalHeight;

      final scaledHeight = (state.pageOriginalHeights[i] ?? 0.0) * scale;
      totalHeight += scaledHeight;

      detectionLineHeight = totalHeight - residualRatio * scaledHeight;
      result.add(detectionLineHeight);

      totalHeight += _separatorHeight;
    }
    _detectionLineHeights = result;

    state = state.copyWith(
      maxScaledPageSumHeight: totalHeight,
      accumulatedScaledPageHeights: accumulatedHeights,
    );
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

  Future<void> onScrollChanged(
    ScrollController scrollController,
    double devicePixelRatio,
  ) async {
    _lastDevicePixelRatio = devicePixelRatio;
    if (state.totalPages == 0 || !scrollController.hasClients) return;
    if (_detectionLineHeights.isEmpty) return;

    final scrollOffset = scrollController.offset;
    int newPage = 0;

    /// From 0 to totalPages-1

    for (
      int i = (state.currentPage - 1).clamp(
        0,
        _detectionLineHeights.length - 1,
      );
      i < _detectionLineHeights.length - 1;
      i++
    ) {
      if (scrollOffset >= _detectionLineHeights[i] &&
          scrollOffset < _detectionLineHeights[i + 1]) {
        newPage = i + 1;
        break;
      }
    }

    if (newPage == 0) {
      if (scrollOffset >= _detectionLineHeights.last) {
        newPage = state.totalPages - 1;
      } else {
        /// fallback: If the quick scroll causes currentPage to lag behind, start from the beginning to find the correct page. This is a trade-off to avoid misidentification of the current page.
        /// 从头开始找，避免快速滚动时 currentPage 跟不上导致的识别错误
        for (int i = 0; i < _detectionLineHeights.length - 1; i++) {
          if (scrollOffset >= _detectionLineHeights[i] &&
              scrollOffset < _detectionLineHeights[i + 1]) {
            newPage = i + 1;
            break;
          }
        }
      }
    }

    if (newPage == 0 && scrollOffset >= _detectionLineHeights.first) {
      throw Exception("暂时无法正确识别当前页");
    }

    newPage = newPage.clamp(0, state.totalPages - 1);

    if (newPage != state.currentPage) {
      state = state.copyWith(currentPage: newPage);
      showPageIndicator();
      _enqueueHighResRender(devicePixelRatio);
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

  void _enqueueHighResRender(double devicePixelRatio) {
    _lastDevicePixelRatio = devicePixelRatio;
    if (state.totalPages == 0) return;

    final int start = (state.currentPage - _highResWindowRadius).clamp(
      0,
      state.totalPages - 1,
    );
    final int end = (state.currentPage + _highResWindowRadius).clamp(
      0,
      state.totalPages - 1,
    );

    // 1) 清理队列中已不在窗口内的过时项（快速滚动后窗口外的入队项）
    _highResRenderQueue.removeWhere((p) => p < start || p > end);

    // 2) 计算 toAdd：窗口内、未缓存、不在队列中、不在渲染中，按距离当前页排序
    final inQueue = _highResRenderQueue.toSet();
    final toAdd = <int>[];
    for (int p = start; p <= end; p++) {
      if (state.highResPageImages.containsKey(p)) continue;
      if (inQueue.contains(p)) continue;
      if (p == _currentlyRenderingPage) continue;
      toAdd.add(p);
    }
    toAdd.sort(
      (a, b) => (a - state.currentPage).abs().compareTo(
        (b - state.currentPage).abs(),
      ),
    );
    // print(toAdd);
    _highResRenderQueue.addAll(toAdd);
    // for (final p in toAdd) {
    //   _highResRenderQueue.addLast(p);
    // }

    // 3) 驱逐窗口外缓存（保留原 addPostFrameCallback 模式以避免帧内 dispose）
    final toRemove = state.highResPageImages.keys
        .where((k) => k < start || k > end)
        .toList();
    if (toRemove.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (toRemove.isEmpty) return;
        final newHighRes = Map<int, ui.Image>.of(state.highResPageImages);
        for (final idx in toRemove) {
          newHighRes[idx]?.dispose();
          newHighRes.remove(idx);
        }
        state = state.copyWith(highResPageImages: newHighRes);
      });
    }
  }

  Future<void> _processHighResQueueTick() async {
    if (_isRenderingHighRes) return; // 上一个还在跑就跳过
    if (_highResRenderQueue.isEmpty) return;

    _isRenderingHighRes = true;
    try {
      while (_highResRenderQueue.isNotEmpty) {
        final int pageIndex = _highResRenderQueue.removeFirst();
        // print(pageIndex);
        // 二次校验：从入队到现在窗口可能已经变了
        final int start = (state.currentPage - _highResWindowRadius).clamp(
          0,
          state.totalPages - 1,
        );
        final int end = (state.currentPage + _highResWindowRadius).clamp(
          0,
          state.totalPages - 1,
        );
        if (pageIndex < start || pageIndex > end) continue;
        if (state.highResPageImages.containsKey(pageIndex)) continue;

        _currentlyRenderingPage = pageIndex;
        try {
          final renderScale = _highResScaleFactor * _lastDevicePixelRatio;
          final result = await _renderPage(pageIndex, scale: renderScale);
          if (result == null || result['success'] != true) continue;

          final img = await _decodeImageFromPixels(
            result['data'],
            result['width'],
            result['height'],
          );
          if (img == null) continue;

          // 三次校验：渲染期间窗口可能已经飘走，避免泄漏 GPU 内存到马上要驱逐的 map
          // final int curStart = (state.currentPage - _highResWindowRadius).clamp(
          //   0,
          //   state.totalPages - 1,
          // );
          // final int curEnd = (state.currentPage + _highResWindowRadius).clamp(
          //   0,
          //   state.totalPages - 1,
          // );
          // if (pageIndex < curStart || pageIndex > curEnd) {
          //   img.dispose();
          //   continue;
          // }

          final newHighRes = Map<int, ui.Image>.of(state.highResPageImages);
          newHighRes[pageIndex] = img;
          state = state.copyWith(highResPageImages: newHighRes);
        } finally {
          _currentlyRenderingPage = null;
        }
      }
    } finally {
      _isRenderingHighRes = false;
    }
  }

  void handlePointerSignal(
    PointerSignalEvent event,
    ScrollController scrollController,
    ScrollController horizontalScrollController,
    double devicePixelRatio,
    double screenWidth,
    double currentPagesMaxWidth,
  ) {
    if (event is PointerScrollEvent && state.isCtrlPressed) {
      final double scrollDelta = event.scrollDelta.dy;
      if (scrollDelta == 0) return;

      final double scaleChange = scrollDelta < 0 ? 0.2 : -0.2;
      final double newScale = (state.globalScale + scaleChange).clamp(0.5, 8.0);
      final newPagesMaxWidth =
          state.originalPagesMaxWidth * newScale / devicePixelRatio;
      double leftPadding = 0;

      if (scrollController.hasClients) {
        _oldScale = state.globalScale;
        _scrollOffset = scrollController.offset;
        _mouseY = event.localPosition.dy;
      }

      if (horizontalScrollController.hasClients) {
        _mouseX = event.localPosition.dx;
        _horizontalScrollOffset = horizontalScrollController.offset;

        if (currentPagesMaxWidth < screenWidth &&
            newPagesMaxWidth >= screenWidth) {
          leftPadding = (screenWidth - currentPagesMaxWidth) / 2;
        } else {
          leftPadding = 0;
        }
      }

      onScaleChanged(
        newScale,
        scrollController,
        horizontalScrollController,
        devicePixelRatio,
        newPagesMaxWidth,
        screenWidth,
        leftPadding,
      );
    } else {
      if (scrollController.hasClients) {
        _scrollOffset = scrollController.offset;
        _mouseY = event.localPosition.dy;
      }
      if (horizontalScrollController.hasClients) {
        _mouseX = event.localPosition.dx;
        _horizontalScrollOffset = horizontalScrollController.offset;
      }
    }
  }

  /// Button-based zoom adjustment (anchors to viewport center).
  void adjustZoom(
    double delta,
    ScrollController scrollController, [
    ScrollController? hController,
  ]) {
    final newScale = (state.globalScale + delta).clamp(0.5, 8.0);
    _oldScale = state.globalScale;
    if (scrollController.hasClients) {
      _scrollOffset = scrollController.offset;
      _mouseY = scrollController.position.viewportDimension / 2;
    }
    if (hController != null && hController.hasClients) {
      _mouseX = hController.position.viewportDimension / 2;
      _horizontalScrollOffset = hController.offset;
    }
    onScaleChanged(newScale, scrollController);
  }

  void onScaleChanged(
    double newScale,
    ScrollController scrollController, [
    ScrollController? horizontalScrollController,
    double devicePixelRatio = 1.0,
    double newPagesMaxWidth = 0,
    double screenWidth = 0,
    double leftPadding = 0,
  ]) {
    state = state.copyWith(globalScale: newScale);

    onPageSizeChanged();

    restoreScrollAfterScale(scrollController);

    restoreHorizontalScrollAfterScale(
      horizontalScrollController,
      newPagesMaxWidth,
      screenWidth,
      leftPadding,
    );
  }

  void onCtrlPressed(bool isCtrlPressed) {
    if (state.isCtrlPressed != isCtrlPressed) {
      state = state.copyWith(isCtrlPressed: isCtrlPressed);
    }
  }

  void onPageSizeChanged() {
    calculateDetectionLineHeights(0.75);
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

    // print(newOffset);

    // final clampedOffset = newOffset.clamp(
    //   scrollController.position.minScrollExtent,
    //   scrollController.position.maxScrollExtent,
    // );

    // print('$newOffset / ${scrollController.position.maxScrollExtent}');

    scrollController.jumpTo(newOffset);
  }

  void restoreHorizontalScrollAfterScale(
    ScrollController? horizontalScrollController,
    double newPagesMaxWidth,
    double screenWidth,
    double leftPadding,
  ) {
    if (horizontalScrollController == null ||
        !horizontalScrollController.hasClients ||
        newPagesMaxWidth < screenWidth) {
      return;
    }
    // print("object");

    final double ratio = state.globalScale / _oldScale;
    final contentXOld = _horizontalScrollOffset + _mouseX - leftPadding;

    final double contentXNew = contentXOld * ratio;
    final double newOffset = contentXNew - _mouseX;

    final clampedOffset = newOffset.clamp(
      horizontalScrollController.position.minScrollExtent,
      newPagesMaxWidth,
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

        final outline = initResult['outline'] as List<OutlineItem>? ?? [];
        // print(outline.first.children.first.title);

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
          originalPagesMaxWidth: originalMaxWidth,
          isLoading: false,
          outline: outline,
        );

        onPageSizeChanged();

        // print('PDF 初始化成功，页数：${state.totalPages}，原始最大宽度：${state.originalMaxWidth}');
        _enqueueHighResRender(devicePixelRatio);
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

  void toggleOutlinePanel() {
    state = state.copyWith(isOutlinePanelOpen: !state.isOutlinePanelOpen);
  }

  void toggleOutlineExpand(String id) {
    final newExpandedIds = Set<String>.from(state.expandedOutlineIds);
    if (newExpandedIds.contains(id)) {
      newExpandedIds.remove(id);
    } else {
      newExpandedIds.add(id);
    }
    state = state.copyWith(expandedOutlineIds: newExpandedIds);
  }

  void jumpToPage(int page, ScrollController scrollController) {
    if (!scrollController.hasClients) return;
    // const double topPadding = .0;
    // const double separatorHeight = 10.0;
    final double gapsHeightAboveCursor =
        (state.accumulatedScaledPageHeights[page]?.toDouble() ?? 0.0);

    scrollController.animateTo(
      gapsHeightAboveCursor,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    // toggleOutlinePanel();
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
    _highResRenderQueue.clear();
    _isRenderingHighRes = false;
    _currentlyRenderingPage = null;
    state = state.copyWith(
      pageImages: {},
      highResPageImages: {},
      totalPages: 0,
      outline: [],
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

    Map<int, List<int>>? pageOriginalSizes;
    final doc = PdfDocument();
    // childReceivePort.t
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
        final outline = doc.getOutline();
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
          'outline': outline,
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
