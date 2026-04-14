import 'dart:isolate';

class PdfReaderState {
  final String? filePath;
  final String? fileHash;
  final int currentPage;
  final int totalPages;
  final String? errorMessage;
  final double globalScale;
  final bool isCtrlPressed;
  final Map<int, double> pageHeights;
  /// Original page sizes: fileHash -> pageIndex -> {width, height}
  final Map<String, Map<int, Map<String, double>>> pageOriginalSizesCache;
  final SendPort? pdfSendPort;

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
    Map<String, Map<int, Map<String, double>>>? pageOriginalSizesCache,
    SendPort? pdfSendPort,
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
    );
  }
}
