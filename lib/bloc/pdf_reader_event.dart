import 'dart:isolate';

abstract class PdfReaderEvent {}

class PickPdfEvent extends PdfReaderEvent {}

class PdfLoadStartedEvent extends PdfReaderEvent {}

class PdfLoadedSuccessEvent extends PdfReaderEvent {
  final String filePath;
  final String fileHash;
  final int totalPages;
  final SendPort pdfSendPort;
  final Map<int, Map<String, double>> pageOriginalSizes;

  PdfLoadedSuccessEvent({
    required this.filePath,
    required this.fileHash,
    required this.totalPages,
    required this.pdfSendPort,
    required this.pageOriginalSizes,
  });
}

class PdfLoadedFailureEvent extends PdfReaderEvent {
  final String errorMessage;

  PdfLoadedFailureEvent(this.errorMessage);
}

class PageChangedEvent extends PdfReaderEvent {
  final int currentPage;

  PageChangedEvent(this.currentPage);
}

class ScaleChangedEvent extends PdfReaderEvent {
  final double scale;

  ScaleChangedEvent(this.scale);
}

class CtrlPressedEvent extends PdfReaderEvent {
  final bool isCtrlPressed;

  CtrlPressedEvent(this.isCtrlPressed);
}

class PageSizeMeasuredEvent extends PdfReaderEvent {
  final int pageIndex;
  final double height;

  PageSizeMeasuredEvent({required this.pageIndex, required this.height});
}

class PageOriginalSizeMeasuredEvent extends PdfReaderEvent {
  final int pageIndex;
  final double originalWidth;
  final double originalHeight;

  PageOriginalSizeMeasuredEvent({
    required this.pageIndex,
    required this.originalWidth,
    required this.originalHeight,
  });
}

class ErrorEvent extends PdfReaderEvent {
  final String errorMessage;

  ErrorEvent(this.errorMessage);
}

class ClearErrorEvent extends PdfReaderEvent {}

class ClosePdfEvent extends PdfReaderEvent {}
