import 'dart:isolate';
import 'dart:ui' as ui;

abstract class PdfReaderEvent {}

class PickPdfEvent extends PdfReaderEvent {}

class PdfLoadStartedEvent extends PdfReaderEvent {}

class PdfLoadedSuccessEvent extends PdfReaderEvent {
  final String filePath;
  final String fileHash;
  final int totalPages;
  final SendPort pdfSendPort;
  final Map<int, List<double>> pageOriginalSizes;

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

class ShowPageIndicatorEvent extends PdfReaderEvent {}

class HidePageIndicatorEvent extends PdfReaderEvent {}

class PageImageRenderedEvent extends PdfReaderEvent {
  final int pageIndex;
  final ui.Image image;

  PageImageRenderedEvent({required this.pageIndex, required this.image});
}

class PageImageClearedEvent extends PdfReaderEvent {
  final int pageIndex;

  PageImageClearedEvent(this.pageIndex);
}

class ClearAllImagesEvent extends PdfReaderEvent {}

class ViewportWidthChangedEvent extends PdfReaderEvent {
  final double viewportWidth;

  ViewportWidthChangedEvent(this.viewportWidth);
}


// 触发页面渲染的事件
class PageRenderRequested extends PdfReaderEvent {
  final int pageIndex;
  final double scale;
  final double devicePixelRatio;
  final Function(int, {double scale}) renderPage;

  PageRenderRequested({
    required this.pageIndex,
    required this.scale,
    required this.devicePixelRatio,
    required this.renderPage,
  });
}

// 记录页面高度的事件 (替代原来的 onSizeChanged)
class PageSizeCalculated extends PdfReaderEvent {
  final int pageIndex;
  final double height;

  PageSizeCalculated(this.pageIndex, this.height);
}