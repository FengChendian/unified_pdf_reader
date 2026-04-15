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
                    isVisible: state.isPageIndicatorVisible,
                    displayedPage: state.displayedPage,
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
        // 通知 bloc 视口宽度变化
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (constraints.maxWidth > 0 &&
              constraints.maxWidth != state.viewportWidth) {
            bloc.add(ViewportWidthChangedEvent(constraints.maxWidth));
          }
        });

        return Listener(
          onPointerSignal: bloc.handlePointerSignal,
          child: state.isHorizontalMode
              ? _buildHorizontalMode(bloc, state)
              : _buildVerticalMode(bloc, state),
        );
      },
    );
  }

  // 横向模式：ListView 水平滚动，多页并排
  Widget _buildHorizontalMode(PdfReaderBloc bloc, PdfReaderState state) {
    return ListView(
      scrollDirection: Axis.horizontal,
      children: [
        Container(
          color: Colors.grey[200],
          child: Center(
            child: SingleChildScrollView(
              key: bloc.listViewKey,
              controller: bloc.vScrollController,
              physics: state.isCtrlPressed
                  ? const NeverScrollableScrollPhysics()
                  : const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                children: [
                  for (int i = 0; i < state.totalPages; i++) ...[
                    _PdfPageWidget(
                      key: ValueKey('page_$i'),
                      pageIndex: i,
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
                    ),
                    if (i < state.totalPages - 1) const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 垂直模式：单列垂直滚动
  Widget _buildVerticalMode(PdfReaderBloc bloc, PdfReaderState state) {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: SingleChildScrollView(
          key: bloc.listViewKey,
          controller: bloc.vScrollController,
          physics: state.isCtrlPressed
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            children: [
              for (int i = 0; i < state.totalPages; i++) ...[
                _PdfPageWidget(
                  key: ValueKey('page_$i'),
                  pageIndex: i,
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
                ),
                if (i < state.totalPages - 1) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
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
  double _measuredHeight = 0.0;
  final GlobalKey _sizeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _requestRender();
    });
  }

  void _measureSize() {
    final renderBox = _sizeKey.currentContext?.findRenderObject() as RenderBox?;
    final actualHeight = renderBox?.size.height ?? 0;
    if (mounted && actualHeight > 0 && actualHeight != _measuredHeight) {
      _measuredHeight = actualHeight;
      widget.onSizeChanged(widget.pageIndex, actualHeight);
    }
  }

  Future<void> _requestRender() async {
    if (!mounted) return;

    final bloc = context.read<PdfReaderBloc>();
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
            bloc.add(
              PageImageRenderedEvent(pageIndex: widget.pageIndex, image: img),
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _measureSize();
            });
          } else {
            img.dispose();
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final devicePixelRatio = View.of(context).devicePixelRatio;

    final bloc = context.read<PdfReaderBloc>();
    final state = bloc.state;
    final pageSizes =
        state.pageOriginalSizesCache[state.fileHash]?[widget.pageIndex];
    final originalWidth = pageSizes?[0] ?? 0.0;
    final originalHeight = pageSizes?[1] ?? 0.0;

    // 使用 BlocListener 监听文件变化
    return BlocListener<PdfReaderBloc, PdfReaderState>(
      listenWhen: (previous, current) => previous.fileHash != current.fileHash,
      listener: (context, state) {
        _requestRender();
      },
      child: _buildPageContent(
        originalWidth,
        originalHeight,
        scale,
        devicePixelRatio,
        state.pageImages[widget.pageIndex],
      ),
    );
  }

  Widget _buildPageContent(
    double originalWidth,
    double originalHeight,
    double scale,
    double devicePixelRatio,
    ui.Image? pageImage,
  ) {
    if (originalWidth == 0 || originalHeight == 0) {
      return Center(
        child: Container(
          width: 595 / devicePixelRatio * scale,
          height: 842 / devicePixelRatio * scale,
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
        child: pageImage == null
            ? SizedBox(
                width: originalWidth / devicePixelRatio * scale,
                height: originalHeight / devicePixelRatio * scale,
                child: const ColoredBox(color: Colors.white),
              )
            : RawImage(
                image: pageImage,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                isAntiAlias: true,
              ),
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  final bool isVisible;
  final int displayedPage;
  final int totalPages;

  const _PageIndicator({
    required this.isVisible,
    required this.displayedPage,
    required this.totalPages,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '$displayedPage / $totalPages',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
