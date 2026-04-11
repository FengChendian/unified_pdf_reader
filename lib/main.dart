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
  ScrollPageMode _scrollPageMode = ScrollPageMode.continuousVertical;

  double _globalScale = 1.0;
  bool _isScaling = false;

  Isolate? _pdfIsolate;
  ReceivePort? _pdfReceivePort;
  SendPort? _pdfSendPort;

  // 处理缩放逻辑，以鼠标指针为中心进行缩放
  void _onScaleChanged(double newScale, Offset globalFocalPoint) {
    if (_globalScale == newScale || !_vScrollController.hasClients) return;

    final oldScale = _globalScale;
    final scaleRatio = newScale / oldScale;
    final currentOffset = _vScrollController.offset;

    // 获取 Scrollable 的 RenderBox 用于坐标转换
    final RenderBox? scrollRenderBox = _vScrollController.position.context.notificationContext?.findRenderObject() as RenderBox?;

    double focalOffsetInContent;
    if (scrollRenderBox != null) {
      // 将全局焦点坐标转换为相对于滚动视图的坐标
      final Offset localFocal = scrollRenderBox.globalToLocal(globalFocalPoint);
      focalOffsetInContent = currentOffset + localFocal.dy;
    } else {
      // 如果无法获取 RenderBox，使用 viewport 中心
      focalOffsetInContent = currentOffset + (_vScrollController.position.viewportDimension / 2);
    }

    setState(() {
      _isScaling = true;
      _globalScale = newScale;
    });

    // 缩放后，让鼠标指针下方的内容保持在同一位置
    // 原理：缩放后，focalOffsetInContent 会变成 focalOffsetInContent * scaleRatio
    // 我们希望这个点在 viewport 中的相对位置不变
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_vScrollController.hasClients) {
        // 缩放后焦点位置在内容空间的新位置
        final double scaledFocalOffset = focalOffsetInContent * scaleRatio;
        // 计算新的滚动位置，使得焦点在 viewport 中的位置保持不变
        final double newOffset = scaledFocalOffset - (focalOffsetInContent - currentOffset);

        _vScrollController.jumpTo(newOffset.clamp(0.0, _vScrollController.position.maxScrollExtent));
      }
      setState(() => _isScaling = false);
    });
  }

  @override
  void dispose() {
    _closePdf();
    _pageController.dispose();
    _vScrollController.dispose();
    super.dispose();
  }

  // --- PDF 加载与 Isolate 逻辑 (保持原逻辑并优化) ---

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
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      _closePdf();
      _pdfReceivePort = ReceivePort();
      _pdfIsolate = await Isolate.spawn(_pdfIsolateEntry, _pdfReceivePort!.sendPort);

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

  Future<Map<String, dynamic>?> _renderPage(int pageIndex, {double scale = 1.0}) async {
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
    setState(() { _errorMessage = msg; _isLoading = false; });
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
        doc = pdfiumBindings.FPDF_LoadMemDocument(fileBuffer!.cast<ffi.Void>(), bytes.length, ffi.nullptr);
        
        if (doc == ffi.nullptr) {
          replyPort.send({'success': false, 'error': 'PDF 载入失败'});
        } else {
          replyPort.send({'success': true, 'pageCount': pdfiumBindings.FPDF_GetPageCount(doc!)});
        }
      } 
      else if (type == 'render') {
        if (doc == null) return;
        final int index = message['pageIndex'];
        final double scale = message['scale'] ?? 1.0;

        final page = pdfiumBindings.FPDF_LoadPage(doc!, index);
        final int width = (pdfiumBindings.FPDF_GetPageWidthF(page) * scale).ceil();
        final int height = (pdfiumBindings.FPDF_GetPageHeightF(page) * scale).ceil();

        final bitmap = pdfiumBindings.FPDFBitmap_Create(width, height, 4);
        pdfiumBindings.FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xFFFFFFFF);
        pdfiumBindings.FPDF_RenderPageBitmap(bitmap, page, 0, 0, width, height, 0, 0x02 | 0x01 | 0x400);

        final buffer = pdfiumBindings.FPDFBitmap_GetBuffer(bitmap);
        final stride = pdfiumBindings.FPDFBitmap_GetStride(bitmap);
        final rawBytes = buffer.cast<ffi.Uint8>().asTypedList(stride * height);
        
        // 快速转换 BGRA 为 RGBA
        final u32list = rawBytes.buffer.asUint32List();
        for (int i = 0; i < u32list.length; i++) {
          final u32 = u32list[i];
          u32list[i] = (u32 & 0xFF00FF00) | ((u32 & 0x00FF0000) >> 16) | ((u32 & 0x000000FF) << 16);
        }

        replyPort.send({
          'success': true,
          'data': Uint8List.fromList(rawBytes),
          'width': width, 'height': height,
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
        title: Text(_filePath?.split(Platform.pathSeparator).last ?? 'PDF Studio'),
        actions: [
          IconButton(icon: const Icon(Icons.folder_open), onPressed: _pickAndLoadPdf),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) return Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)));
    if (_pdfSendPort == null) return const Center(child: Text("请打开 PDF 文件"));

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          color: Colors.grey[200],
          child: ListView.builder(
            controller: _vScrollController,
            itemCount: _totalPages,
            cacheExtent: 3000, 
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemBuilder: (context, index) {
              return _PdfPageWidget(
                key: ValueKey('${_filePath}_$index'),
                pageIndex: index,
                renderPage: _renderPage,
                scale: _globalScale,
                onScaleChanged: _onScaleChanged,
              );
            },
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
  final Function(double, Offset) onScaleChanged;

  const _PdfPageWidget({
    super.key,
    required this.pageIndex,
    required this.renderPage,
    required this.scale,
    required this.onScaleChanged,
  });

  @override
  State<_PdfPageWidget> createState() => _PdfPageWidgetState();
}

class _PdfPageWidgetState extends State<_PdfPageWidget> with AutomaticKeepAliveClientMixin {
  ui.Image? _currentImage; // 当前显示的图片
  ui.Image? _pendingImage; // 正在后台解码的新图
  bool _isRendering = false;
  Timer? _debounceTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _requestRender();
  }

  @override
  void didUpdateWidget(_PdfPageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scale != widget.scale) {
      // 缩放时，取消之前的定时器，重新计时
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 1), () {
        _requestRender();
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _currentImage?.dispose();
    _pendingImage?.dispose();
    super.dispose();
  }

  Future<void> _requestRender() async {
    if (!mounted || _isRendering) return;
    
    _isRendering = true;
    final dpr = ui.window.devicePixelRatio;
    // 渲染倍率：缩放比例 * 屏幕像素比 * 基础清晰度系数
    final renderScale = widget.scale * dpr * 1.5; 

    final result = await widget.renderPage(widget.pageIndex, scale: renderScale);
    
    if (result != null && result['success'] && mounted) {
      ui.decodeImageFromPixels(
        result['data'],
        result['width'],
        result['height'],
        ui.PixelFormat.rgba8888,
        (img) {
          if (mounted) {
            setState(() {
              // 替换逻辑：
              // 将新图置入，由于使用了 Stack，新图会覆盖在旧图之上
              final oldImg = _currentImage;
              _currentImage = img;
              // 延迟销毁旧图，确保渲染完成，彻底消除闪烁
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

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final isControlPressed = HardwareKeyboard.instance.logicalKeysPressed.any((key) => 
        [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight, 
         LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight].contains(key));

      if (isControlPressed) {
        final double delta = -event.scrollDelta.dy / 1000;
        final double newScale = (widget.scale + delta).clamp(1.0, 5.0);
        widget.onScaleChanged(newScale, event.position);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // 计算页面显示尺寸
    final screenWidth = MediaQuery.of(context).size.width;
    final displayWidth = (screenWidth - 40) * widget.scale;

    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
          width: displayWidth,
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
          ),
          child: _currentImage == null 
            ? const AspectRatio(aspectRatio: 0.7, child: Center(child: CircularProgressIndicator()))
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 50),
                transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                child: RawImage(
                  key: ValueKey(_currentImage.hashCode),
                  image: _currentImage,
                  fit: BoxFit.contain, // 自定义或使用 BoxFit.contain
                  scale: View.of(context).devicePixelRatio * 1.5, // 对应渲染时的倍率
                ),
              ),
        ),
      ),
    );
  }
}