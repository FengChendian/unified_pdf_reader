import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' as ffi_pkg;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart';
import 'pdf_reader_event.dart';
import 'pdf_reader_state.dart';
import 'package:flutter/rendering.dart';
class PdfReaderBloc extends Bloc<PdfReaderEvent, PdfReaderState> {
  Isolate? _pdfIsolate;
  ReceivePort? _pdfReceivePort;
  SendPort? _pdfSendPort;

  double _oldScale = 1.0;
  double _scrollOffset = 0.0;
  double _mouseY = 0.0;

  List<double> _detectionLineHeights = [];

  static const double _separatorHeight = 10.0;
  static const double _verticalPadding = 5.0;

  /// 计算检测线位置的实际高度
  ///
  /// [ratio] - 检测线位置，0.0 表示每个组件顶部，1.0 表示每个组件底部
  /// 返回所有页面在检测线位置的实际高度数组（最后一个元素是列表底部padding之后的位置）
  List<double> calculateDetectionLineHeights(double ratio) {
    final result = <double>[];

    for (int i = 0; i < state.totalPages; i++) {
      // 顶部 padding
      double height = _verticalPadding;

      // 累加前面所有页面的高度和 separator
      for (int j = 0; j < i; j++) {
        height += state.pageHeights[j] ?? 0.0;
        height += _separatorHeight;
      }

      // 累加当前页面的检测线位置
      height += (state.pageHeights[i] ?? 0.0) * ratio;

      result.add(height);
    }

    // 计算总高度（包含底部 padding）
    double totalHeight = _verticalPadding;
    for (int i = 0; i < state.totalPages; i++) {
      totalHeight += state.pageHeights[i] ?? 0.0;
      if (i < state.totalPages - 1) {
        totalHeight += _separatorHeight;
      }
    }
    // print(state.pageHeights[2]);
    totalHeight += _verticalPadding;

    // 添加一个标记，表示列表结束后的检测线位置
    result.add(totalHeight);

    return result;
  }

  final PageController pageController = PageController();
  final ScrollController vScrollController = ScrollController();
  final GlobalKey listViewKey = GlobalKey();

  Function(double scale)? onRestoreScrollAfterScale;

  PdfReaderBloc() : super(const PdfReaderState()) {
    on<PickPdfEvent>(_onPickPdf);
    on<PdfLoadStartedEvent>(_onPdfLoadStarted);
    on<PdfLoadedSuccessEvent>(_onPdfLoadedSuccess);
    on<PdfLoadedFailureEvent>(_onPdfLoadedFailure);
    on<PageChangedEvent>(_onPageChanged);
    on<ScaleChangedEvent>(_onScaleChanged);
    on<CtrlPressedEvent>(_onCtrlPressed);
    on<PageSizeMeasuredEvent>(_onPageSizeMeasured);

    on<ErrorEvent>(_onError);
    on<ClearErrorEvent>(_onClearError);
    on<ClosePdfEvent>(_onClosePdf);

    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    vScrollController.addListener(_onScrollChanged);
  }

  @override
  Future<void> close() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _closePdf();
    pageController.dispose();
    vScrollController.dispose();
    return super.close();
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
      add(CtrlPressedEvent(isCtrl));
    }
    return false;
  }



  void _onScrollChanged() {
    _updateCurrentPage();
  }

  void _updateCurrentPage() {
    if (state.totalPages == 0 || !vScrollController.hasClients) return;
    if (_detectionLineHeights.isEmpty) return;

    final scrollOffset = vScrollController.offset;
    
    int newPage = 0;

    for (int i = 0; i < _detectionLineHeights.length - 1; i++) {
      if (scrollOffset >= _detectionLineHeights[i] &&
          scrollOffset < _detectionLineHeights[i + 1]) {
        // scroll 在 detection line i 和 i+1 之间，页码为 (i + 1)
        newPage = i + 1;
        break;
      }
    }

    newPage = newPage.clamp(0, state.totalPages - 1);

    if (newPage != state.currentPage) {
      add(PageChangedEvent(newPage));
    }
  }

  void handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && state.isCtrlPressed) {
      final double scrollDelta = event.scrollDelta.dy;
      if (scrollDelta == 0) return;

      final double scaleChange = scrollDelta < 0 ? 0.2 : -0.2;
      final double targetScale = (state.globalScale + scaleChange).clamp(
        0.5,
        5.0,
      );

      if (vScrollController.hasClients) {
        _oldScale = state.globalScale;
        _scrollOffset = vScrollController.offset;
        _mouseY = event.localPosition.dy;
      }

      add(ScaleChangedEvent(targetScale));
      restoreScrollAfterScale(_oldScale, targetScale);
    } else {

      if (vScrollController.hasClients) {
        _scrollOffset = vScrollController.offset;
        _mouseY = event.localPosition.dy;
      }
    }
  }

  void restoreScrollAfterScale(double oldScale, double newScale) {
    if (!vScrollController.hasClients) return;

    const double topPadding = 5.0;
    const double bottomPadding = 5.0;
    const double separatorHeight = 10.0;

    // print(state.currentPage);
    // 6. 计算鼠标光标上方，一共有多少高度是“固定间距”
    final double gapsHeightAboveCursor =
        topPadding + ((state.currentPage) * (separatorHeight));

    // 7. 剥离光标上方的间距，提取出旧的“纯内容 Y 坐标”
    final double pureContentYOld =
        (_scrollOffset + _mouseY) - gapsHeightAboveCursor;

    final double ratio = newScale / oldScale;

    final double pureContentYNew = pureContentYOld * ratio;


    // 10. 计算新的 offset 并跳转
    final double newOffset =
        (pureContentYNew + gapsHeightAboveCursor) - _mouseY;
      // final double newOffset =
      //     ratio * _mouseY;
    if (newOffset <= 0) {
      vScrollController.jumpTo(0);
      return;
    }
    final clampedOffset = newOffset.clamp(
      vScrollController.position.minScrollExtent,
      vScrollController.position.maxScrollExtent,
    );

    vScrollController.jumpTo(clampedOffset);
  }

  Future<void> _onPickPdf(
    PickPdfEvent event,
    Emitter<PdfReaderState> emit,
  ) async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(type: FileType.any);
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        if (!path.toLowerCase().endsWith('.pdf')) {
          add(ErrorEvent('请选择 PDF 文件'));
          return;
        }
        add(PdfLoadStartedEvent());
        await _initPdfIsolate(path, emit);
      }
    } catch (e) {
      add(ErrorEvent('选择文件失败: $e'));
    }
  }

  Future<void> _initPdfIsolate(
    String path,
    Emitter<PdfReaderState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearErrorMessage: true));
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
        final pageOriginalSizes = initResult['pageOriginalSizes'] as Map<int, Map<String, double>>? ?? {};
        add(
          PdfLoadedSuccessEvent(
            filePath: path,
            fileHash: fileHash,
            totalPages: initResult['pageCount'],
            pdfSendPort: _pdfSendPort!,
            pageOriginalSizes: pageOriginalSizes,
          ),
        );
      } else {
        add(PdfLoadedFailureEvent(initResult['error']));
      }
    } catch (e) {
      add(PdfLoadedFailureEvent('加载 PDF 异常: $e'));
    }
  }

  void _onPdfLoadStarted(
    PdfLoadStartedEvent event,
    Emitter<PdfReaderState> emit,
  ) {
    emit(state.copyWith(isLoading: true, clearErrorMessage: true));
  }

  void _onPdfLoadedSuccess(
    PdfLoadedSuccessEvent event,
    Emitter<PdfReaderState> emit,
  ) {
    final pageOriginalSizesCache = {event.fileHash: event.pageOriginalSizes};
    emit(
      state.copyWith(
        filePath: event.filePath,
        fileHash: event.fileHash,
        totalPages: event.totalPages,
        pdfSendPort: event.pdfSendPort,
        pageOriginalSizesCache: pageOriginalSizesCache,
        isLoading: false,
      ),
    );
  }

  void _onPdfLoadedFailure(
    PdfLoadedFailureEvent event,
    Emitter<PdfReaderState> emit,
  ) {
    emit(state.copyWith(isLoading: false, errorMessage: event.errorMessage));
  }

  void _onPageChanged(PageChangedEvent event, Emitter<PdfReaderState> emit) {
    if (event.currentPage != state.currentPage) {
      emit(state.copyWith(currentPage: event.currentPage));
    }
  }

  void _onScaleChanged(ScaleChangedEvent event, Emitter<PdfReaderState> emit) {
    emit(state.copyWith(globalScale: event.scale));
  }

  void _onCtrlPressed(CtrlPressedEvent event, Emitter<PdfReaderState> emit) {
    if (event.isCtrlPressed != state.isCtrlPressed) {
      emit(state.copyWith(isCtrlPressed: event.isCtrlPressed));
    }
  }

  void _onPageSizeMeasured(
    PageSizeMeasuredEvent event,
    Emitter<PdfReaderState> emit,
  ) {
    if (state.pageHeights[event.pageIndex] != event.height) {
      final newPageHeights = Map<int, double>.from(state.pageHeights);
      newPageHeights[event.pageIndex] = event.height;
      emit(state.copyWith(pageHeights: newPageHeights));
      _detectionLineHeights = calculateDetectionLineHeights(0.75);
      _updateCurrentPage();
    }
  }

  void _onError(ErrorEvent event, Emitter<PdfReaderState> emit) {
    emit(state.copyWith(errorMessage: event.errorMessage, isLoading: false));
  }

  void _onClearError(ClearErrorEvent event, Emitter<PdfReaderState> emit) {
    emit(state.copyWith(clearErrorMessage: true));
  }

  void _onClosePdf(ClosePdfEvent event, Emitter<PdfReaderState> emit) {
    _closePdf();
    emit(const PdfReaderState());
  }

  void _closePdf() {
    _pdfReceivePort?.close();
    _pdfIsolate?.kill(priority: Isolate.immediate);
    _pdfIsolate = null;
    _pdfSendPort = null;
  }

  Future<Map<String, dynamic>?> renderPage(
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
    Map<int, Map<String, double>>? pageOriginalSizes;

    childReceivePort.listen((message) {
      final String type = message['type'];
      final SendPort replyPort = message['replyPort'];

      if (type == 'init') {
        final Uint8List bytes = message['pdfBytes'];
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
          pageOriginalSizes = <int, Map<String, double>>{};
          for (int i = 0; i < pageCount; i++) {
            final page = pdfiumBindings.FPDF_LoadPage(doc!, i);
            pageOriginalSizes![i] = {
              'width': pdfiumBindings.FPDF_GetPageWidthF(page),
              'height': pdfiumBindings.FPDF_GetPageHeightF(page),
            };
            pdfiumBindings.FPDF_ClosePage(page);
          }
          replyPort.send({
            'success': true,
            'pageCount': pageCount,
            'pageOriginalSizes': pageOriginalSizes,
          });
        }
      } else if (type == 'render') {
        if (doc == null || pageOriginalSizes == null) return;
        final int index = message['pageIndex'];
        final double scale = message['scale'] ?? 1.0;
        final sizes = pageOriginalSizes!;

        final page = pdfiumBindings.FPDF_LoadPage(doc!, index);
        final pageSize = sizes[index];
        final double originalWidth = pageSize!['width']!;
        final double originalHeight = pageSize['height']!;

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
          0x02 | 0x01 | 0x400,
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
