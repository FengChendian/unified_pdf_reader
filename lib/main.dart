import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'bloc/pdf_reader_bloc.dart';
import 'bloc/pdf_reader_event.dart';
import 'bloc/pdf_reader_state.dart';

void main() {
  runApp(const PdfReaderApp());
}

class PdfReaderApp extends StatelessWidget {
  const PdfReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PdfReaderBloc(),
      child: MaterialApp(
        title: 'PDF Studio Pro',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
          useMaterial3: true,
        ),
        home: const PdfReaderPage(),
      ),
    );
  }
}

class PdfReaderPage extends StatelessWidget {
  const PdfReaderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PdfReaderBloc, PdfReaderState>(
      builder: (context, state) {
        final bloc = context.read<PdfReaderBloc>();
        return Scaffold(
          appBar: AppBar(
            title: Text(
              state.filePath?.split(Platform.pathSeparator).last ??
                  'PDF Studio',
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.folder_open),
                onPressed: () => bloc.add(PickPdfEvent()),
              ),
            ],
          ),
          body: Stack(
            children: [
              _buildBody(context, bloc, state),
              if (state.totalPages > 0)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _PageIndicator(
                    currentPage: state.currentPage + 1,
                    totalPages: state.totalPages,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    PdfReaderBloc bloc,
    PdfReaderState state,
  ) {
    if (state.errorMessage != null) {
      return Center(
        child: Text(
          state.errorMessage!,
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    if (state.pdfSendPort == null) {
      return const Center(child: Text("请打开 PDF 文件"));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          onPointerSignal: bloc.handlePointerSignal,
          child: Container(
            color: Colors.grey[200],
            child: ListView.separated(
              key: bloc.listViewKey,
              controller: bloc.vScrollController,
              physics: state.isCtrlPressed
                  ? const NeverScrollableScrollPhysics()
                  : const ClampingScrollPhysics(),
              itemCount: state.totalPages,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              cacheExtent: 2000,
              padding: const EdgeInsets.symmetric(vertical: 5),
              itemBuilder: (context, index) {
                return _PdfPageWidget(
                  key: ValueKey('page_$index'),
                  pageIndex: index,
                  renderPage: bloc.renderPage,
                  scale: state.globalScale,
                  onSizeChanged: (pageIndex, height) {
                    bloc.add(
                      PageSizeMeasuredEvent(
                        pageIndex: pageIndex,
                        height: height,
                      ),
                    );
                  },
                  onOriginalSizeChanged: (pageIndex, width, height) {
                    bloc.add(
                      PageOriginalSizeMeasuredEvent(
                        pageIndex: pageIndex,
                        originalWidth: width,
                        originalHeight: height,
                      ),
                    );
                  },
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
  final Function(int, {double scale}) renderPage;
  final double scale;
  final void Function(int pageIndex, double height) onSizeChanged;
  final void Function(int pageIndex, double width, double height)
      onOriginalSizeChanged;

  const _PdfPageWidget({
    super.key,
    required this.pageIndex,
    required this.renderPage,
    required this.scale,
    required this.onSizeChanged,
    required this.onOriginalSizeChanged,
  });

  @override
  State<_PdfPageWidget> createState() => _PdfPageWidgetState();
}

class _PdfPageWidgetState extends State<_PdfPageWidget> {
  ui.Image? _currentImage;
  bool _isRendering = false;
  Timer? _debounceTimer;
  bool _disposed = false;
  double _measuredHeight = 0.0;
  final GlobalKey _sizeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) _requestRender();
    });
  }

  @override
  void didUpdateWidget(_PdfPageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.scale != widget.scale) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 150), () {
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

  void _measureSize() {
    final renderBox = _sizeKey.currentContext?.findRenderObject() as RenderBox?;
    final actualHeight = renderBox?.size.height ?? 0;
    if (!_disposed && actualHeight > 0 && actualHeight != _measuredHeight) {
      _measuredHeight = actualHeight;
      widget.onSizeChanged(widget.pageIndex, actualHeight);
    }
  }

  Future<void> _requestRender() async {
    if (!mounted || _isRendering) return;

    _isRendering = true;
    final dpr = View.of(context).devicePixelRatio;
    final renderScale = widget.scale * dpr;

    final result = await widget.renderPage(
      widget.pageIndex,
      scale: renderScale,
    );

    if (result != null && result['success'] && mounted) {
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
                _measureSize();
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
    final scale = widget.scale;
    final devicePixelRatio = View.of(context).devicePixelRatio;

    final bloc = context.read<PdfReaderBloc>();
    final state = bloc.state;
    final pageSizes = state.pageOriginalSizesCache[state.fileHash]?[widget.pageIndex];
    final originalWidth = pageSizes?['width'] ?? 0.0;
    final originalHeight = pageSizes?['height'] ?? 0.0;

    if (originalWidth == 0 || originalHeight == 0) {
      return Center(
        child: Container(
          width: 595 / devicePixelRatio * scale,
          height: 842 / devicePixelRatio * scale,
          // padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.white,
        ),
      );
    }

    return SizedBox(
      key: _sizeKey,
      width: originalWidth / devicePixelRatio * scale,
      height: originalHeight / devicePixelRatio * scale,
      child: FittedBox(
        fit: BoxFit.contain,
        child: _currentImage == null
            ? SizedBox(
                width: originalWidth / devicePixelRatio * scale,
                height: originalHeight / devicePixelRatio * scale,
                child: const ColoredBox(color: Colors.white),
              )
            : RawImage(
                image: _currentImage,
                fit: BoxFit.contain,
                filterQuality: ui.FilterQuality.high,
              ),
      ),
    );
  }
}

class _PageIndicator extends StatefulWidget {
  final int currentPage;
  final int totalPages;

  const _PageIndicator({required this.currentPage, required this.totalPages});

  @override
  State<_PageIndicator> createState() => _PageIndicatorState();
}

class _PageIndicatorState extends State<_PageIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  int _displayedPage = 0;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _displayedPage = widget.currentPage;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void didUpdateWidget(_PageIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPage != widget.currentPage) {
      _displayedPage = widget.currentPage;
      _controller.reset();
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '$_displayedPage / ${widget.totalPages}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }
}
