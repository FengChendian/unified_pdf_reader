import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'providers/pdf_reader_provider.dart';

void main() {
  runApp(
    ProviderScope(
      child: PdfReaderApp(),
    ),
  );
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

class PdfReaderPage extends HookConsumerWidget {
  const PdfReaderPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pdfReaderProvider);
    final notifier = ref.read(pdfReaderProvider.notifier);

    useEffect(() {
      notifier.initialize();
      return () => notifier.dispose();
    }, []);

    final scrollController = useScrollController();
    final listViewKey = useMemoized(() => notifier.listViewKey, []);

    useEffect(() {
      void listener() {
        notifier.onScrollChanged(scrollController);
      }

      scrollController.addListener(listener);
      return () => scrollController.removeListener(listener);
    }, [scrollController]);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          state.filePath?.split('\\').last ?? 'PDF Studio',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: () => notifier.pickPdf(View.of(context).devicePixelRatio),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(context, ref, notifier, scrollController, listViewKey, state),
          if (state.totalPages > 0)
            Positioned(
              right: 16,
              bottom: 16,
              child: PageIndicator(
                isVisible: state.isPageIndicatorVisible,
                displayedPage: state.displayedPage,
                totalPages: state.totalPages,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    PdfReaderNotifier notifier,
    ScrollController scrollController,
    GlobalKey listViewKey,
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
        if (constraints.maxWidth > 0 &&
            constraints.maxWidth != state.viewportWidth) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            notifier.onViewportWidthChanged(constraints.maxWidth);
          });
        }

        return Listener(
          onPointerSignal: (event) =>
              notifier.handlePointerSignal(event, scrollController),
          child: state.isHorizontalMode
              ? _buildHorizontalMode(notifier, state, scrollController, listViewKey)
              : _buildVerticalMode(notifier, state, scrollController, listViewKey),
        );
      },
    );
  }

  Widget _buildHorizontalMode(
    PdfReaderNotifier notifier,
    PdfReaderState state,
    ScrollController scrollController,
    GlobalKey listViewKey,
  ) {
    return ListView(
      scrollDirection: Axis.horizontal,
      children: [
        Container(
          color: Colors.grey[200],
          child: Center(
            child: SingleChildScrollView(
              key: listViewKey,
              controller: scrollController,
              physics: state.isCtrlPressed
                  ? const NeverScrollableScrollPhysics()
                  : const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                children: [
                  for (int i = 0; i < state.totalPages; i++) ...[
                    PdfPageWidget(
                      key: ValueKey('${state.fileHash}_page_$i'),
                      pageIndex: i,
                      scale: state.globalScale,
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

  Widget _buildVerticalMode(
    PdfReaderNotifier notifier,
    PdfReaderState state,
    ScrollController scrollController,
    GlobalKey listViewKey,
  ) {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: SingleChildScrollView(
          key: listViewKey,
          controller: scrollController,
          physics: state.isCtrlPressed
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            children: [
              for (int i = 0; i < state.totalPages; i++) ...[
                PdfPageWidget(
                  key: ValueKey('page_$i'),
                  pageIndex: i,
                  scale: state.globalScale,
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

class PdfPageWidget extends HookConsumerWidget {
  final int pageIndex;
  final double scale;

  const PdfPageWidget({
    super.key,
    required this.pageIndex,
    required this.scale,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pdfReaderProvider);
    // final notifier = ref.read(pdfReaderProvider.notifier);
    final devicePixelRatio = View.of(context).devicePixelRatio;

    final pageSizes = state.pageOriginalSizesCache[state.fileHash]?[pageIndex];
    final originalWidth = pageSizes?[0] ?? 0.0;
    final originalHeight = pageSizes?[1] ?? 0.0;

    // useEffect(() {
    //   if (originalHeight > 0) {
    //     WidgetsBinding.instance.addPostFrameCallback((_) {
    //       notifier.onPageSizeMeasured(
    //         pageIndex,
    //         originalHeight / devicePixelRatio * scale,
    //       );
    //     });
    //   }
    //   return null;
    // }, [originalHeight, scale, devicePixelRatio]);

    return _buildPageContent(
      originalWidth,
      originalHeight,
      scale,
      devicePixelRatio,
      state.pageImages[pageIndex],
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
                filterQuality: FilterQuality.medium,
                isAntiAlias: true,
              ),
      ),
    );
  }
}

class PageIndicator extends StatelessWidget {
  final bool isVisible;
  final int displayedPage;
  final int totalPages;

  const PageIndicator({
    super.key,
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
