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

/// Tab 信息
class TabInfo {
  final String fileHash;
  final String filePath;
  final String fileName;
  const TabInfo({
    required this.fileHash,
    required this.filePath,
    required this.fileName,
  });
}

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
  final int originalPagesMaxWidth;
  final bool isLoading;
  final List<OutlineItem> outline;
  final bool isOutlinePanelOpen;
  final Set<String> expandedOutlineIds;
  final double savedScrollOffset;

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
    this.savedScrollOffset = 0.0,
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
    double? savedScrollOffset,
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
      savedScrollOffset: savedScrollOffset ?? this.savedScrollOffset,
    );
  }
}

/// PDF 阅读器 Notifier（每个文档一个实例，通过 family provider 管理）
class PdfReaderNotifier extends Notifier<PdfReaderState> {
  final String fileHash;

  PdfReaderNotifier(this.fileHash);
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

  static const int _highResWindowRadius = 2;
  static const Duration _highResRenderInterval = Duration(milliseconds: 100);

  @override
  PdfReaderState build() {
    ref.onDispose(() {
      fullDispose();
    });
    return const PdfReaderState();
  }

  // ─── 生命周期：首次打开 ────────────────────────────────────────────────

  Future<void> fullInit(String path, double devicePixelRatio) async {
    await _initPdf(path, devicePixelRatio);
    _startHighResTimer();
    _enqueueHighResRender(devicePixelRatio);
  }

  // ─── 生命周期：切回已打开的文档（isolate 和缓存都还在） ──────────────

  void resume(String path, double devicePixelRatio) {
    _startHighResTimer();
    _enqueueHighResRender(devicePixelRatio);
  }

  // ─── 生命周期：切走（保留 isolate、端口、高低清缓存） ────────────────

  void suspend() {
    _stopHighResTimer();
    _highResRenderQueue.clear();
    _isRenderingHighRes = false;
    _currentlyRenderingPage = null;
  }

  // ─── 生命周期：关闭（全部清理） ────────────────────────────────────────

  void fullDispose() {
    _stopHighResTimer();
    _hideIndicatorTimer?.cancel();
    _highResRenderQueue.clear();
    _isRenderingHighRes = false;
    _currentlyRenderingPage = null;
    _killIsolate();
    _pdfReceivePort?.close();
    _pdfReceivePort = null;
    _pdfSendPort = null;

    for (final image in state.pageImages.values) {
      image.dispose();
    }
    for (final image in state.highResPageImages.values) {
      image.dispose();
    }
    state = const PdfReaderState();
  }

  /// 供 Workspace 在切 tab 前保存滚动位置
  void saveScrollOffset(double offset) {
    state = state.copyWith(savedScrollOffset: offset);
  }

  // ─── 内部 init ─────────────────────────────────────────────────────────

  Future<void> _initPdf(String path, double devicePixelRatio) async {
    try {
      _killIsolate();
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

        final pageHeights = <int, double>{};
        for (int i = 0; i < initResult['pageCount']; i++) {
          pageHeights[i] =
              (pageOriginalSizes[i]?[1].toDouble() ?? 0.0) / devicePixelRatio;
        }

        final outline = initResult['outline'] as List<OutlineItem>? ?? [];

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
      } else {
        state = state.copyWith(errorMessage: initResult['error'] as String);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: '加载 PDF 异常：$e');
    }
  }

  void _killIsolate() {
    _pdfIsolate?.kill(priority: Isolate.immediate);
    _pdfIsolate = null;
  }

  void _startHighResTimer() {
    _highResRenderTimer?.cancel();
    _highResRenderTimer = Timer.periodic(
      _highResRenderInterval,
      (_) => _processHighResQueueTick(),
    );
  }

  void _stopHighResTimer() {
    _highResRenderTimer?.cancel();
    _highResRenderTimer = null;
  }

  // ─── 滚动 / 页面检测 ──────────────────────────────────────────────────

  void calculateDetectionLineHeights(double ratio) {
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

  Future<void> onScrollChanged(
    ScrollController scrollController,
    double devicePixelRatio,
  ) async {
    _lastDevicePixelRatio = devicePixelRatio;
    if (state.totalPages == 0 || !scrollController.hasClients) return;
    if (_detectionLineHeights.isEmpty) return;

    final scrollOffset = scrollController.offset;
    int newPage = 0;

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

  // ─── 图片解码 ──────────────────────────────────────────────────────────

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

    // _highResRenderQueue.removeWhere((p) => p < start || p > end);

    // final inQueue = _highResRenderQueue.toSet();
    final toAdd = <int>[];
    for (int p = start; p <= end; p++) {
      toAdd.add(p);
    }
    toAdd.sort(
      (a, b) => (a - state.currentPage).abs().compareTo(
        (b - state.currentPage).abs(),
      ),
    );
    _highResRenderQueue.addAll(toAdd);

    final toRemove = state.highResPageImages.keys
        .where((k) => k < start || k > end)
        .toList();

    if (toRemove.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // if (toRemove.isEmpty) return;
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
    if (_isRenderingHighRes) return;
    if (_highResRenderQueue.isEmpty) return;

    _isRenderingHighRes = true;
    try {
      while (_highResRenderQueue.isNotEmpty) {
        while (_highResRenderQueue.length >( _highResWindowRadius * 2 + 1)) {
          // 队列过长时优先渲染当前页附近的页面
          _highResRenderQueue.removeFirst();
        }
        final int pageIndex = _highResRenderQueue.remove(state.currentPage)
            ? state.currentPage
            : _highResRenderQueue.removeFirst();
        // _highResRenderQueu
        if (state.highResPageImages.containsKey(pageIndex)) continue;

        // final int start = (state.currentPage - _highResWindowRadius).clamp(
        //   0,
        //   state.totalPages - 1,
        // );
        // final int end = (state.currentPage + _highResWindowRadius).clamp(
        //   0,
        //   state.totalPages - 1,
        // );
        // if (pageIndex < start || pageIndex > end) continue;
        

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

  // ─── 指针 / 缩放 ─────────────────────────────────────────────────────

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

  void adjustZoom(
    double delta,
    ScrollController scrollController,
    double devicePixelRatio,
    double screenWidth,
    double currentPagesMaxWidth, [
    ScrollController? hController,
  ]) {
    final newScale = (state.globalScale + delta).clamp(0.5, 8.0);
    _oldScale = state.globalScale;
    if (scrollController.hasClients) {
      _scrollOffset = scrollController.offset;
      _mouseY = scrollController.position.viewportDimension / 2;
    }

    final newPagesMaxWidth =
        state.originalPagesMaxWidth * newScale / devicePixelRatio;
    double leftPadding = 0;

    if (hController != null && hController.hasClients) {
      _mouseX = hController.position.viewportDimension / 2;
      _horizontalScrollOffset = hController.offset;

      if (currentPagesMaxWidth < screenWidth &&
          newPagesMaxWidth >= screenWidth) {
        leftPadding = (screenWidth - currentPagesMaxWidth) / 2;
      }
    }
    onScaleChanged(
      newScale,
      scrollController,
      hController,
      devicePixelRatio,
      newPagesMaxWidth,
      screenWidth,
      leftPadding,
    );
  }

  void onScaleChanged(
    double newScale,
    ScrollController scrollController,
    ScrollController? horizontalScrollController,
    double devicePixelRatio,
    double newPagesMaxWidth,
    double screenWidth,
    double leftPadding,
  ) {
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

    final double ratio = state.globalScale / _oldScale;
    final contentXOld = _horizontalScrollOffset + _mouseX - leftPadding;

    final double contentXNew = contentXOld * ratio;
    final double newOffset = contentXNew - _mouseX;

    final clampedOffset = newOffset.clamp(
      horizontalScrollController.position.minScrollExtent,
      newPagesMaxWidth,
    );
    horizontalScrollController.jumpTo(clampedOffset);
  }

  // ─── UI 辅助 ──────────────────────────────────────────────────────────

  void clearError() {
    state = state.copyWith(clearErrorMessage: true);
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
    final double gapsHeightAboveCursor =
        (state.accumulatedScaledPageHeights[page]?.toDouble() ?? 0.0);

    scrollController.animateTo(
      gapsHeightAboveCursor,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // ─── 内部渲染 / Isolate ──────────────────────────────────────────────

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

    childReceivePort.listen((message) {
      final String type = message['type'];
      final SendPort replyPort = message['replyPort'];

      if (type == 'init') {
        final renderedPixedMap = <int, Uint8List>{};
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
      }
    });
  }
}

/// 工作区状态
class WorkspaceState {
  final List<TabInfo> openTabs;
  final String? activeTabId;

  const WorkspaceState({this.openTabs = const [], this.activeTabId});

  WorkspaceState copyWith({
    List<TabInfo>? openTabs,
    String? activeTabId,
    bool clearActiveTabId = false,
  }) {
    return WorkspaceState(
      openTabs: openTabs ?? this.openTabs,
      activeTabId: clearActiveTabId ? null : (activeTabId ?? this.activeTabId),
    );
  }
}

/// 工作区 Notifier
class WorkspaceNotifier extends Notifier<WorkspaceState> {
  @override
  WorkspaceState build() {
    ref.onDispose(() {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    });
    return const WorkspaceState();
  }

  void initialize() {
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
  }

  Future<void> openPdf(double devicePixelRatio) async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(type: FileType.any);
      if (result == null || result.files.single.path == null) return;

      final path = result.files.single.path!;
      if (!path.toLowerCase().endsWith('.pdf')) return;

      final bytes = await File(path).readAsBytes();
      final fileHash = md5.convert(bytes).toString();

      final existingIndex = state.openTabs.indexWhere(
        (t) => t.fileHash == fileHash,
      );
      if (existingIndex != -1) {
        switchToTab(fileHash);
        return;
      }

      final fileName = path.split(Platform.pathSeparator).last;

      final newTab = TabInfo(
        fileHash: fileHash,
        filePath: path,
        fileName: fileName,
      );

      final wasActive = state.activeTabId;
      if (wasActive != null) {
        ref.read(pdfReaderProvider(wasActive).notifier).suspend();
      }

      state = state.copyWith(
        openTabs: [...state.openTabs, newTab],
        activeTabId: fileHash,
      );

      await ref
          .read(pdfReaderProvider(fileHash).notifier)
          .fullInit(path, devicePixelRatio);
    } catch (_) {}
  }

  void switchToTab(String fileHash) {
    if (state.activeTabId == fileHash) return;
    if (!state.openTabs.any((t) => t.fileHash == fileHash)) return;

    final oldTabId = state.activeTabId;
    if (oldTabId != null) {
      ref.read(pdfReaderProvider(oldTabId).notifier).suspend();
    }

    state = state.copyWith(activeTabId: fileHash);

    final tab = state.openTabs.firstWhere((t) => t.fileHash == fileHash);
    ref
        .read(pdfReaderProvider(fileHash).notifier)
        .resume(
          tab.filePath,
          1.0, // dpr will be updated on first scroll/layout
        );
  }

  void goHome() {
    if (state.activeTabId == null) return;

    ref.read(pdfReaderProvider(state.activeTabId!).notifier).suspend();
    state = state.copyWith(clearActiveTabId: true);
  }

  void closeTab(String fileHash) {
    ref.read(pdfReaderProvider(fileHash).notifier).fullDispose();

    final newTabs = state.openTabs
        .where((t) => t.fileHash != fileHash)
        .toList();

    String? newActiveId;
    if (state.activeTabId == fileHash) {
      if (newTabs.isNotEmpty) {
        final closedIndex = state.openTabs.indexWhere(
          (t) => t.fileHash == fileHash,
        );
        final newIndex = closedIndex < newTabs.length
            ? closedIndex
            : newTabs.length - 1;
        newActiveId = newTabs[newIndex].fileHash;
      }
    } else {
      newActiveId = state.activeTabId;
    }

    state = state.copyWith(
      openTabs: newTabs,
      activeTabId: newActiveId,
      clearActiveTabId: newActiveId == null,
    );

    if (newActiveId != null && newActiveId != fileHash) {
      final tab = state.openTabs.firstWhere((t) => t.fileHash == newActiveId);
      ref
          .read(pdfReaderProvider(newActiveId).notifier)
          .resume(tab.filePath, 1.0);
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    final isCtrl = HardwareKeyboard.instance.logicalKeysPressed.any(
      (key) =>
          key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight ||
          key == LogicalKeyboardKey.metaLeft ||
          key == LogicalKeyboardKey.metaRight,
    );

    final activeTabId = state.activeTabId;
    if (activeTabId != null) {
      ref.read(pdfReaderProvider(activeTabId).notifier).onCtrlPressed(isCtrl);
    }
    return false;
  }
}

// ─── Provider 声明 ──────────────────────────────────────────────────────

final pdfReaderProvider =
    NotifierProvider.family<PdfReaderNotifier, PdfReaderState, String>(
      (fileHash) => PdfReaderNotifier(fileHash),
    );

final workspaceProvider = NotifierProvider<WorkspaceNotifier, WorkspaceState>(
  WorkspaceNotifier.new,
);
