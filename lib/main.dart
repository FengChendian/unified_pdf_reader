import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:unified_pdf_reader/cache_list.dart';
import 'package:unified_pdf_reader/mupdf/mupdf.dart';
import 'package:unified_pdf_reader/scrollbar.dart';
import 'providers/pdf_reader_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Must add this line.
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = WindowOptions(
    size: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(ProviderScope(child: PdfReaderApp()));
}

class PdfReaderApp extends StatelessWidget {
  const PdfReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final VirtualWindowFrameBuilder = VirtualWindowFrameInit();
    return MaterialApp(
      title: 'PDF Studio Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5C6BC0), // 更高级的蓝紫
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),

        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black87,
        ),

        iconTheme: const IconThemeData(size: 20, color: Colors.black54),

        textTheme: GoogleFonts.notoSansScTextTheme(),
      ),
      builder: (context, child) => VirtualWindowFrameBuilder(context, child),
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
    // final listViewKey = useMemoized(() => notifier.listViewKey, []);

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

    final outline = ref.watch(
      pdfReaderProvider.select((state) => state.outline),
    );
    final isOutlinePanelOpen = ref.watch(
      pdfReaderProvider.select((state) => state.isOutlinePanelOpen),
    );

    return Scaffold(
      body: Column(
        children: [
          _buildTitleBar(filePath),
          _buildToolbar(context, ref, notifier),
          Expanded(
            child: Stack(
              children: [
                _buildBody(
                  context,
                  ref,
                  notifier,
                  scrollController,
                  horizontalScrollController,
                  // listViewKey,
                ),
                if (outline.isNotEmpty && isOutlinePanelOpen)
                  _buildOutlinePanel(context, ref, notifier, scrollController),
                if (filePath != null)
                  const Positioned(
                    right: 16,
                    bottom: 16,
                    child: PageIndicator(),
                  ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: CustomScrollbar(
                    controller: scrollController,
                    thickness: 6,
                    radius: const Radius.circular(3),
                    color: const Color(0xFF9CA3AF),
                  ),
                ),
              ],
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
    ScrollController horizontalScrollController,
    // GlobalKey listViewKey,
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
    final originalPagesMaxWidth = ref.watch(
      pdfReaderProvider.select((state) => state.originalPagesMaxWidth),
    );
    final globalScale = ref.watch(
      pdfReaderProvider.select((state) => state.globalScale),
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
    final devicePixelRatio = View.of(context).devicePixelRatio;
    final currentMaxWidth =
        originalPagesMaxWidth * globalScale / devicePixelRatio;

    // useEffect(() {
    //   if (originalMaxWidth > 0) {
    //     WidgetsBinding.instance.addPostFrameCallback((_) {
    //       notifier.onViewportWidthChanged(currentMaxWidth, screenWidth);
    //     });
    //   }
    //   return null;
    // }, [originalMaxWidth, screenWidth]);

    return Listener(
      onPointerSignal: (event) => notifier.handlePointerSignal(
        event,
        scrollController,
        horizontalScrollController,
        devicePixelRatio,
        screenWidth,
        currentMaxWidth,
      ),
      child: _buildPdfView(
        context,
        notifier,
        isCtrlPressed,
        totalPages,
        fileHash,
        scrollController,
        horizontalScrollController,
        // listViewKey,
        pageHeights,
        currentMaxWidth,
        globalScale,
      ),
    );
  }

  Widget _buildPdfView(
    BuildContext context,
    PdfReaderNotifier notifier,
    bool isCtrlPressed,
    int totalPages,
    String? fileHash,
    ScrollController scrollController,
    ScrollController horizontalScrollController,
    // GlobalKey listViewKey,
    Map<int, double>? pageHeights,
    double currentMaxWidth,
    double globalScale,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;

    final heightsOnDevice = List<double>.generate(totalPages * 2, (index) {
      if (index.isOdd) {
        return 10; // separator height
      }

      final pageIndex = index ~/ 2;
      if (pageHeights != null && pageHeights[pageIndex] != null) {
        return pageHeights[pageIndex]! * globalScale;
      } else {
        return 842 / View.of(context).devicePixelRatio * globalScale; // 默认高度
      }
    });

    return Container(
      // color: Colors.grey[200],
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF5F7FA), Color(0xFFEDEFF3)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        controller: horizontalScrollController,
        children: [
          SizedBox(
            width: math.max(currentMaxWidth, screenWidth),
            child: ScrollConfiguration(
              behavior: const ScrollBehavior().copyWith(scrollbars: false),
              child: CustomScrollView(
                // key: listViewKey,
                controller: scrollController,
                physics: isCtrlPressed
                    ? const NeverScrollableScrollPhysics()
                    : const ClampingScrollPhysics(),
                slivers: [
                  VariedExtentList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (index.isOdd) {
                        return const SizedBox(height: 10);
                      }

                      final i = index ~/ 2;
                      return PdfPageWidget(
                        key: ValueKey('page_${fileHash}_$i'),
                        pageIndex: i,
                      );
                    }, childCount: totalPages * 2),
                    itemExtents: heightsOnDevice,
                    // globalScale: globalScale,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    // return Container(
    //   // color: Colors.grey[200],
    //   decoration: const BoxDecoration(
    //     gradient: LinearGradient(
    //       colors: [Color(0xFFF5F7FA), Color(0xFFEDEFF3)],
    //       begin: Alignment.topCenter,
    //       end: Alignment.bottomCenter,
    //     ),
    //   ),
    //   child: ListView(
    //     scrollDirection: Axis.horizontal,
    //     controller: horizontalScrollController,
    //     children: [
    //       SizedBox(
    //         width: math.max(currentMaxWidth, screenWidth),
    //         child: ListView.builder(
    //           itemCount: totalPages * 2,
    //           itemExtentBuilder: (index, dimensions) {
    //             // if (pageHeights != null) {
    //             if (index.isEven) {
    //               // print(1);
    //               if (pageHeights![index ~/ 2] != null) {
    //                 // print('Height for page ${index ~/ 2} is not available yet.');
    //                 return pageHeights[index ~/ 2]! * globalScale;
    //               } else {
    //                 return 842 /
    //                     View.of(context).devicePixelRatio *
    //                     globalScale; // 默认高度
    //               }
    //             } else {
    //               return 10; // separator height
    //             }
    //             // }
    //             // return ;
    //           },
    //           // key: listViewKey,
    //           controller: scrollController,
    //           physics: isCtrlPressed
    //               ? const NeverScrollableScrollPhysics()
    //               : const ClampingScrollPhysics(),
    //           padding: const EdgeInsets.symmetric(vertical: 5),
    //           itemBuilder: (context, index) {
    //             if (index.isOdd) {
    //               return const SizedBox(height: 10);
    //             } else {
    //               final i = index ~/ 2;
    //               return PdfPageWidget(
    //                 key: ValueKey('page_${fileHash}_$i'),
    //                 pageIndex: i,
    //               );
    //             }
    //           },
    //         ),
    //       ),
    //     ],
    //   ),
    // );
  }

  Widget _buildTitleBar(String? filePath) {
    return GestureDetector(
      onPanStart: (details) => windowManager.startDragging(),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.blue[50],
          // border: Border(
          //   bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
          // ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              const Icon(
                Icons.picture_as_pdf,
                size: 18,
                color: Colors.redAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  filePath?.split('\\').last ?? 'PDF Studio',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ), // Positioned.fill(child: MoveWindow()),
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    WidgetRef ref,
    PdfReaderNotifier notifier,
  ) {
    final outline = ref.watch(
      pdfReaderProvider.select((state) => state.outline),
    );

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.blue[50]),
      child: Row(
        children: [
          if (outline.isNotEmpty)
            _toolbarButton(
              icon: Icons.menu_book_outlined,
              tooltip: '目录',
              onTap: notifier.toggleOutlinePanel,
            ),
          const Spacer(),
          _toolbarButton(
            icon: Icons.folder_open_rounded,
            tooltip: '打开文件',
            onTap: () async =>
                await notifier.pickPdf(View.of(context).devicePixelRatio),
          ),
        ],
      ),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(padding: const EdgeInsets.all(8), child: Icon(icon)),
      ),
    );
  }

  Widget _buildOutlinePanel(
    BuildContext context,
    WidgetRef ref,
    PdfReaderNotifier notifier,
    ScrollController scrollController,
  ) {
    final outline = ref.watch(
      pdfReaderProvider.select((state) => state.outline),
    );
    final expandedIds = ref.watch(
      pdfReaderProvider.select((state) => state.expandedOutlineIds),
    );

    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      child: Material(
        elevation: 4,
        child: Container(
          width: 280,
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '目录',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: notifier.toggleOutlinePanel,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: OutlineTreeWidget(
                  items: outline,
                  expandedIds: expandedIds,
                  onToggleExpand: notifier.toggleOutlineExpand,
                  onJumpToPage: (page) =>
                      notifier.jumpToPage(page, scrollController),
                ),
              ),
            ],
          ),
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
  const PageIndicator({super.key});

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

class OutlineTreeWidget extends HookConsumerWidget {
  final List<OutlineItem> items;
  final Set<String> expandedIds;
  final void Function(String id) onToggleExpand;
  final void Function(int page) onJumpToPage;
  final int depth;

  const OutlineTreeWidget({
    super.key,
    required this.items,
    required this.expandedIds,
    required this.onToggleExpand,
    required this.onJumpToPage,
    this.depth = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 只在 depth=0 时使用 ListView 避免循环嵌套
    if (depth == 0) {
      return ListView.builder(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final id = '${item.title}_${item.page}_${depth}_$index';
          final isExpanded = expandedIds.contains(id);
          final hasChildren = item.children.isNotEmpty;
          return OutlineItemWidget(
            item: item,
            id: id,
            isExpanded: isExpanded,
            hasChildren: hasChildren,
            expandedIds: expandedIds,
            onToggleExpand: onToggleExpand,
            onJumpToPage: onJumpToPage,
            depth: depth,
          );
        },
      );
    }

    // 子级使用 Column 避免递归 ListView
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        final id = '${item.title}_${item.page}_${depth}_$index';
        final isExpanded = expandedIds.contains(id);
        final hasChildren = item.children.isNotEmpty;
        return OutlineItemWidget(
          item: item,
          id: id,
          isExpanded: isExpanded,
          hasChildren: hasChildren,
          expandedIds: expandedIds,
          onToggleExpand: onToggleExpand,
          onJumpToPage: onJumpToPage,
          depth: depth,
        );
      }).toList(),
    );
  }
}

class OutlineItemWidget extends HookWidget {
  final OutlineItem item;
  final String id;
  final bool isExpanded;
  final bool hasChildren;
  final Set<String> expandedIds;
  final void Function(String id) onToggleExpand;
  final void Function(int page) onJumpToPage;
  final int depth;

  const OutlineItemWidget({
    super.key,
    required this.item,
    required this.id,
    required this.isExpanded,
    required this.hasChildren,
    required this.expandedIds,
    required this.onToggleExpand,
    required this.onJumpToPage,
    required this.depth,
  });

  @override
  Widget build(BuildContext context) {
    final isHovered = useState(false);

    final bool isRoot = depth == 0;

    // 1. 统一处理点击事件
    void Function()? onTapHandler;
    if (hasChildren) {
      onTapHandler = () => onToggleExpand(id);
    } else if (item.page >= 0) {
      onTapHandler = () => onJumpToPage(item.page);
    }

    // 2. 提取差异化样式与缩进配置
    final double iconSize = isRoot ? 18.0 : 16.0;
    final double fontSize = isRoot ? 13.0 : 12.0;
    final FontWeight fontWeight = isRoot ? FontWeight.w500 : FontWeight.normal;

    // 根节点容器无内边距，子节点根据 depth 逐级计算内边距
    final EdgeInsetsGeometry containerPadding = isRoot
        ? EdgeInsets.zero
        : EdgeInsets.only(left: 12 + (depth - 1) * 16.0);

    // 3. 构建子节点树 (如果展开的话)
    Widget? childrenTreeWidget;
    if (hasChildren && isExpanded) {
      childrenTreeWidget = OutlineTreeWidget(
        items: item.children,
        expandedIds: expandedIds,
        onToggleExpand: onToggleExpand,
        onJumpToPage: onJumpToPage,
        depth: depth + 1,
      );

      // 根节点的子树独有外层 24 的 Padding 缩进
      if (isRoot) {
        childrenTreeWidget = Padding(
          padding: const EdgeInsets.only(left: 24),
          child: childrenTreeWidget,
        );
      }
    }

    // 4. 统一的结构渲染
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          onEnter: (_) => isHovered.value = true,
          onExit: (_) => isHovered.value = false,
          cursor: onTapHandler != null
              ? SystemMouseCursors.click
              : MouseCursor.defer,
          child: InkWell(
            onTap: onTapHandler,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Container(
              height: 32,
              padding: containerPadding,
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  if (hasChildren)
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        size: iconSize,
                        // color: Colors.black54,
                      ),
                    )
                  else
                    const SizedBox(width: 24),
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        fontSize: fontSize,
                        color: isHovered.value ? Colors.blue : Colors.black87,

                        fontWeight: fontWeight,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 如果有子树并且处于展开状态，则渲染子树
        ?childrenTreeWidget,
      ],
    );
  }
}
