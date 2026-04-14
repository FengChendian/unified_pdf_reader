import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;
import 'dart:ffi' as ffi;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart';
import 'package:ffi/ffi.dart' as ffi_pkg;

void main() {
  runApp(const PdfReaderApp());
}

class PdfReaderApp extends StatelessWidget {
  const PdfReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Studio Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const PdfReaderPage(),
    );
  }
}

class PdfReaderPage extends StatefulWidget {
  const PdfReaderPage({super.key});

  @override
  State<PdfReaderPage> createState() => _PdfReaderPageState();
}

enum ScrollPageMode { continuousVertical }

class _PdfReaderPageState extends State<PdfReaderPage> {
  String? _filePath;
  int _currentPage = 0;
  int _totalPages = 0;
  bool _isLoading = false;
  String? _errorMessage;

  final PageController _pageController = PageController();
  final ScrollController _vScrollController = ScrollController();
  final GlobalKey _listViewKey = GlobalKey();

  double _globalScale = 1.0;
  double _oldScale = 1.0;
  double _scrollOffset = 0.0;
  double _mouseY = 0.0;
  bool _isCtrlPressed = false;

  Isolate? _pdfIsolate;
  ReceivePort? _pdfReceivePort;
  SendPort? _pdfSendPort;

  @override
  void initState() {
    super.initState();
    // 注册键盘监听，用于识别 Ctrl 键
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _closePdf();
    _pageController.dispose();
    _vScrollController.dispose();
    super.dispose();
  }

  // 监听 Ctrl/Cmd 键的按下与抬起
  bool _handleKeyEvent(KeyEvent event) {
    final isCtrl = HardwareKeyboard.instance.logicalKeysPressed.any(
      (key) =>
          key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight ||
          key == LogicalKeyboardKey.metaLeft ||
          key == LogicalKeyboardKey.metaRight,
    );

    if (_isCtrlPressed != isCtrl) {
      setState(() {
        _isCtrlPressed = isCtrl;
      });
    }
    return false;
  }

  // 使用滚轮缩放，保持鼠标指向的内容位置不变
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && _isCtrlPressed) {
      final double scrollDelta = event.scrollDelta.dy;
      if (scrollDelta == 0) return;

      // 缩放因子：往上滚放大，往下滚缩小
      final double scaleChange = scrollDelta < 0 ? 1.1 : 0.9;
      final double targetScale = (_globalScale * scaleChange).clamp(0.5, 5.0);

      if (_vScrollController.hasClients) {
        _oldScale = _globalScale;
        _scrollOffset = _vScrollController.offset;
        _mouseY = event.localPosition.dy;
      }

      setState(() {
        _globalScale = targetScale;
        _restoreScrollAfterScale();
      });

      // _restoreScrollAfterScale();
    }
  }

  Future<void> _restoreScrollAfterScale() async {
    // if (!_vScrollController.hasClients) return;

    // await Future.delayed(const Duration(milliseconds: 50));
    if (!_vScrollController.hasClients) return;

    final ratio = _globalScale / _oldScale;
    // 缩放后，保持鼠标位置下的内容坐标不变
    final newOffset = (_scrollOffset + _mouseY) * ratio - _mouseY;
    final clampedOffset = newOffset.clamp(
      _vScrollController.position.minScrollExtent,
      _vScrollController.position.maxScrollExtent,
    );
    _vScrollController.jumpTo(clampedOffset);
  }

  // --- PDF 加载与 Isolate 逻辑 ---

  Future<void> _pickAndLoadPdf() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(type: FileType.any);
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        if (!path.toLowerCase().endsWith('.pdf')) {
          _showError('请选择 PDF 文件');
          return;
        }
        await _initPdfIsolate(path);
      }
    } catch (e) {
      _showError('选择文件失败: $e');
    }
  }

  Future<void> _initPdfIsolate(String path) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
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
      final responsePort = ReceivePort();
      _pdfSendPort!.send({
        'type': 'init',
        'pdfBytes': bytes,
        'replyPort': responsePort.sendPort,
      });

      final initResult = await responsePort.first;
      responsePort.close();

      if (initResult['success']) {
        setState(() {
          _filePath = path;
          _totalPages = initResult['pageCount'];
          _currentPage = 0;
          _isLoading = false;
        });
      } else {
        _showError(initResult['error']);
      }
    } catch (e) {
      _showError('加载 PDF 异常: $e');
    }
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

  void _closePdf() {
    _pdfReceivePort?.close();
    _pdfIsolate?.kill(priority: Isolate.immediate);
    _pdfIsolate = null;
    _pdfSendPort = null;
  }

  void _showError(String msg) {
    setState(() {
      _errorMessage = msg;
      _isLoading = false;
    });
  }

  static void _pdfIsolateEntry(SendPort mainSendPort) {
    final childReceivePort = ReceivePort();
    mainSendPort.send([childReceivePort.sendPort]);

    pdfiumBindings.FPDF_InitLibrary();
    FPDF_DOCUMENT? doc;
    ffi.Pointer<ffi.Uint8>? fileBuffer;

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
          replyPort.send({
            'success': true,
            'pageCount': pdfiumBindings.FPDF_GetPageCount(doc!),
          });
        }
      } else if (type == 'render') {
        if (doc == null) return;
        final int index = message['pageIndex'];
        final double scale = message['scale'] ?? 1.0;

        final page = pdfiumBindings.FPDF_LoadPage(doc!, index);
        final int width = (pdfiumBindings.FPDF_GetPageWidthF(page) * scale)
            .ceil();
        final int height = (pdfiumBindings.FPDF_GetPageHeightF(page) * scale)
            .ceil();

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

        // 快速转换 BGRA 为 RGBA
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
          'originalWidth': pdfiumBindings.FPDF_GetPageWidthF(page),
          'originalHeight': pdfiumBindings.FPDF_GetPageHeightF(page),
        });

        pdfiumBindings.FPDFBitmap_Destroy(bitmap);
        pdfiumBindings.FPDF_ClosePage(page);
      }
    });
  }

  // --- UI 构建 ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _filePath?.split(Platform.pathSeparator).last ?? 'PDF Studio',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _pickAndLoadPdf,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return Center(
        child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (_pdfSendPort == null) return const Center(child: Text("请打开 PDF 文件"));

    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          onPointerSignal: _handlePointerSignal,
          child: Container(
            color: Colors.grey[200],
            child: ListView.separated(
              key: _listViewKey,
              controller: _vScrollController,
              // 按下 Ctrl 时禁用自身滚动，只允许缩放，防止事件冲突
              physics: _isCtrlPressed
                  ? const NeverScrollableScrollPhysics()
                  : const ClampingScrollPhysics(),
              itemCount: _totalPages,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              cacheExtent: 3000,
              padding: const EdgeInsets.symmetric(vertical: 5),
              itemBuilder: (context, index) {
                return _PdfPageWidget(
                  key: ValueKey('${_filePath}_$index'),
                  pageIndex: index,
                  renderPage: _renderPage,
                  scale: _globalScale,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _PdfPageWidget extends StatefulWidget {
  final int pageIndex;
  final Future<Map<String, dynamic>?> Function(int, {double scale}) renderPage;
  final double scale;

  const _PdfPageWidget({
    super.key,
    required this.pageIndex,
    required this.renderPage,
    required this.scale,
  });

  @override
  State<_PdfPageWidget> createState() => _PdfPageWidgetState();
}

class _PdfPageWidgetState extends State<_PdfPageWidget>
    with AutomaticKeepAliveClientMixin {
  ui.Image? _currentImage;
  bool _isRendering = false;
  Timer? _debounceTimer;
  double _originalWidth = 0.0;
  double _originalHeight = 0.0;
  bool _disposed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) _requestRender();
    });
  }

  // 监听缩放变化并触发高清渲染
  @override
  void didUpdateWidget(_PdfPageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scale != widget.scale) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 200), () {
        if (!_disposed) _requestRender();
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _currentImage?.dispose();
    super.dispose();
  }

  Future<void> _requestRender() async {
    if (!mounted || _isRendering) return;

    _isRendering = true;
    final dpr = View.of(context).devicePixelRatio;
    final renderScale = widget.scale * dpr * 1.5;

    final result = await widget.renderPage(
      widget.pageIndex,
      scale: renderScale,
    );

    if (result != null && result['success'] && mounted) {
      _originalWidth = result['originalWidth'] ?? 0.0;
      _originalHeight = result['originalHeight'] ?? 0.0;

      ui.decodeImageFromPixels(
        result['data'],
        result['width'],
        result['height'],
        ui.PixelFormat.rgba8888,
        (img) {
          if (mounted) {
            setState(() {
              final oldImg = _currentImage;
              _currentImage = img;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                oldImg?.dispose();
              });
            });
          } else {
            img.dispose();
          }
        },
      );
    }
    _isRendering = false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_originalWidth == 0 || _originalHeight == 0) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final scale = widget.scale;
    final devicePixelRatio = View.of(context).devicePixelRatio;

    return SizedBox(
      width: _originalWidth / devicePixelRatio * scale,
      height: _originalHeight / devicePixelRatio * scale,
      child: FittedBox(
        fit: BoxFit.contain,
        child: _currentImage == null
            ? const Center(child: CircularProgressIndicator())
            : RawImage(
                image: _currentImage,
                fit: BoxFit.contain,
                filterQuality: ui.FilterQuality.high,
              ),
      ),
    );
  }
}