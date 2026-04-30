import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'providers/pdf_reader_provider.dart';

void main() {
  runApp(ProviderScope(child: PdfReaderApp()));
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
    // final state = ref.watch(pdfReaderProvider);
    final filePath = ref.watch(
      pdfReaderProvider.select((state) => state.filePath),
    );

    // final errorMessage = ref.watch(pdfReaderProvider.select((state) => state.errorMessage));
    final notifier = ref.read(pdfReaderProvider.notifier);

    useEffect(() {
      notifier.initialize();
      return () => notifier.dispose();
    }, [notifier]);

    final scrollController = useScrollController();
    final horizontalScrollController = useScrollController();
    final listViewKey = useMemoized(() => notifier.listViewKey, []);

    useEffect(() {
      void listener() async {
        await notifier.onScrollChanged(
          scrollController,
          View.of(context).devicePixelRatio,
        );
      }

      scrollController.addListener(listener);
      return () => scrollController.removeListener(listener);
    }, [scrollController]);

    return Scaffold(
      appBar: AppBar(
        title: Text(filePath?.split('\\').last ?? 'PDF Studio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: () async =>
                await notifier.pickPdf(View.of(context).devicePixelRatio),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(
            context,
            ref,
            notifier,
            scrollController,
            horizontalScrollController,
            listViewKey,
            // state,
          ),
          if (filePath != null)
            Positioned(right: 16, bottom: 16, child: PageIndicator()),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    PdfReaderNotifier notifier,
    ScrollController scrollController,
    ScrollController horizontalScrollController,
    GlobalKey listViewKey,
  ) {
    final errorMessage = ref.watch(
      pdfReaderProvider.select((state) => state.errorMessage),
    );
    final isLoading = ref.watch(
      pdfReaderProvider.select((state) => state.isLoading),
    );
    final pdfSendPort = ref.watch(
      pdfReaderProvider.select((state) => state.pdfSendPort),
    );
    final originalMaxWidth = ref.watch(
      pdfReaderProvider.select((state) => state.originalMaxWidth),
    );
    final globalScale = ref.watch(
      pdfReaderProvider.select((state) => state.globalScale),
    );

    final viewportWidth = ref.watch(
      pdfReaderProvider.select((state) => state.viewportWidth),
    );

    final isHorizontalMode = ref.watch(
      pdfReaderProvider.select((state) => state.isHorizontalMode),
    );

    final isCtrlPressed = ref.watch(
      pdfReaderProvider.select((state) => state.isCtrlPressed),
    );

    final totalPages = ref.watch(
      pdfReaderProvider.select((state) => state.totalPages),
    );

    final fileHash = ref.watch(
      pdfReaderProvider.select((state) => state.fileHash),
    );

    final pageHeights = ref.watch(
      pdfReaderProvider.select((state) => state.pageOriginalHeights),
    );

    if (errorMessage != null) {
      return Center(
        child: Text(errorMessage, style: const TextStyle(color: Colors.red)),
      );
    }
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (pdfSendPort == null) {
      return const Center(child: Text("请打开 PDF 文件"));
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final currentMaxWidth =
        originalMaxWidth * globalScale / View.of(context).devicePixelRatio;

    useEffect(() {
      if (currentMaxWidth != viewportWidth) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifier.onViewportWidthChanged(currentMaxWidth, screenWidth);
        });
      }
      return null;
    }, [currentMaxWidth, viewportWidth]);

    return Listener(
      onPointerSignal: (event) => notifier.handlePointerSignal(
        event,
        scrollController,
        horizontalScrollController: horizontalScrollController,
      ),
      child: isHorizontalMode
          ? _buildHorizontalMode(
              context,
              notifier,
              isCtrlPressed,
              totalPages,
              fileHash,
              scrollController,
              horizontalScrollController,
              listViewKey,
              pageHeights,
              currentMaxWidth,
              globalScale,
            )
          : _buildVerticalMode(
              context,
              notifier,
              isCtrlPressed,
              totalPages,
              fileHash,
              scrollController,
              listViewKey,
              pageHeights,
              globalScale,
            ),
    );
  }

  Widget _buildHorizontalMode(
    BuildContext context,
    PdfReaderNotifier notifier,
    // PdfReaderState state,
    bool isCtrlPressed,
    int totalPages,
    String? fileHash,
    ScrollController scrollController,
    ScrollController horizontalScrollController,
    GlobalKey listViewKey,
    Map<int, double>? pageHeights,
    double currentMaxWidth,
    double globalScale,
  ) {
    return ListView(
      scrollDirection: Axis.horizontal,
      controller: horizontalScrollController,
      children: [
        SizedBox(
          width: currentMaxWidth,
          child: ColoredBox(
            color: Colors.grey[200]!,
            child: Center(
              child: ListView.builder(
                itemCount: totalPages * 2,
                itemExtentBuilder: (index, dimensions) {
                  if (pageHeights != null) {
                    if (index.isEven) {
                      return pageHeights[index ~/ 2]! * globalScale;
                    } else {
                      return 10; // separator height
                    }
                  }
                  return null;
                },
                key: listViewKey,
                controller: scrollController,
                physics: isCtrlPressed
                    ? const NeverScrollableScrollPhysics()
                    : const ClampingScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 5),
                itemBuilder: (context, index) {
                  if (index.isOdd) {
                    return const SizedBox(height: 10);
                  } else {
                    // print(index);
                    final i = index ~/ 2;

                    return PdfPageWidget(
                      key: ValueKey('page_$i'),
                      pageIndex: i,
                    );
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalMode(
    BuildContext context,
    PdfReaderNotifier notifier,
    bool isCtrlPressed,
    int totalPages,
    String? fileHash,
    ScrollController scrollController,
    GlobalKey listViewKey,
    Map<int, double>? pageHeights,
    double globalScale,
  ) {
    return Container(
      color: Colors.grey[200],
      child: SizedBox(
        width: MediaQuery.of(context).size.width,
        child: ListView.builder(
          itemCount: totalPages * 2,
          itemExtentBuilder: (index, dimensions) {
            if (pageHeights != null) {
              if (index.isEven) {
                return pageHeights[index ~/ 2]! * globalScale;
              } else {
                return 10; // separator height
              }
            }
            return null;
          },
          key: listViewKey,
          controller: scrollController,
          physics: isCtrlPressed
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 5),
          itemBuilder: (context, index) {
            if (index.isOdd) {
              return const SizedBox(height: 10);
            } else {
              // print(index);
              final i = index ~/ 2;

              return PdfPageWidget(key: ValueKey('page_$i'), pageIndex: i);
            }
          },
        ),
      ),
    );
  }
}

class PdfPageWidget extends HookConsumerWidget {
  final int pageIndex;

  const PdfPageWidget({super.key, required this.pageIndex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicePixelRatio = View.of(context).devicePixelRatio;

    final pageSizes = ref.watch(
      pdfReaderProvider.select(
        (state) => state.docRawPageSizes[state.fileHash]?[pageIndex],
      ),
    );
    final originalWidth = pageSizes?[0] ?? 0;
    final originalHeight = pageSizes?[1] ?? 0;

    final pageImage = ref.watch(
      pdfReaderProvider.select(
        (state) =>
            state.highResPageImages[pageIndex] ?? state.pageImages[pageIndex],
      ),
    );

    final scale = ref.watch(
      pdfReaderProvider.select((state) => state.globalScale),
    );

    // print(pageIndex);

    return _buildPageContent(
      originalWidth,
      originalHeight,
      scale,
      devicePixelRatio,
      pageImage,
    );
  }

  Widget _buildPageContent(
    int originalWidth,
    int originalHeight,
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
                // isAntiAlias: true,
              ),
      ),
    );
  }
}

class PageIndicator extends HookConsumerWidget {
  const PageIndicator({
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalPages = ref.watch(
      pdfReaderProvider.select((state) => state.totalPages),
    );
    final isPageIndicatorVisible = ref.watch(
      pdfReaderProvider.select((state) => state.isPageIndicatorVisible),
    );
    final displayedPage = ref.watch(
      pdfReaderProvider.select((state) => state.displayedPage),
    );
    return AnimatedOpacity(
      opacity: isPageIndicatorVisible ? 1.0 : 0.0,
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
