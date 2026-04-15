import 'dart:isolate';
import 'dart:ui' as ui;

class PdfReaderState {
  final String? filePath;
  final String? fileHash;
  final int currentPage;
  final int totalPages;
  final String? errorMessage;
  final double globalScale;
  final bool isCtrlPressed;
  final Map<int, double> pageHeights;
  /// Original page sizes: fileHash -> pageIndex -> [width, height]
  final Map<String, Map<int, List<double>>> pageOriginalSizesCache;
  
  final SendPort? pdfSendPort;
  final bool isPageIndicatorVisible;
  final int displayedPage;
  /// Rendered page images: pageIndex -> ui.Image
  final Map<int, ui.Image> pageImages;
  final double viewportWidth;
  final bool isHorizontalMode;

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
    this.viewportWidth = 0.0,
    this.isHorizontalMode = false,
  });

  PdfReaderState copyWith({
    String? filePath,
    String? fileHash,
    int? currentPage,
    int? totalPages,
    bool? isLoading,
    String? errorMessage,
    double? globalScale,
    bool? isCtrlPressed,
    Map<int, double>? pageHeights,
    Map<String, Map<int, List<double>>>? pageOriginalSizesCache,
    SendPort? pdfSendPort,
    bool? isPageIndicatorVisible,
    int? displayedPage,
    Map<int, ui.Image>? pageImages,
    double? viewportWidth,
    bool? isHorizontalMode,
    bool clearFilePath = false,
    bool clearErrorMessage = false,
  }) {
    return PdfReaderState(
      filePath: clearFilePath ? null : (filePath ?? this.filePath),
      fileHash: fileHash ?? this.fileHash,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      globalScale: globalScale ?? this.globalScale,
      isCtrlPressed: isCtrlPressed ?? this.isCtrlPressed,
      pageHeights: pageHeights ?? this.pageHeights,
      pageOriginalSizesCache: pageOriginalSizesCache ?? this.pageOriginalSizesCache,
      pdfSendPort: pdfSendPort ?? this.pdfSendPort,
      isPageIndicatorVisible: isPageIndicatorVisible ?? this.isPageIndicatorVisible,
      displayedPage: displayedPage ?? this.displayedPage,
      pageImages: pageImages ?? this.pageImages,
      viewportWidth: viewportWidth ?? this.viewportWidth,
      isHorizontalMode: isHorizontalMode ?? this.isHorizontalMode,
    );
  }
}
