import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../utils/cache_list.dart';
import '../constants/app_colors.dart';
import '../constants/mock_data.dart';
import '../mupdf/mupdf.dart';
import '../providers/pdf_reader_provider.dart';
import '../widgets/scrollbar.dart';
import '../widgets/document_tab.dart';
import '../widgets/history_document_card.dart';
import '../widgets/new_document_card.dart';
import '../widgets/outline_tree.dart';
import '../widgets/page_indicator.dart';
import '../widgets/pdf_page_widget.dart';
import '../widgets/sidebar_button.dart';

class PdfReaderPage extends HookConsumerWidget {
  const PdfReaderPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceNotifier = ref.read(workspaceProvider.notifier);
    final activeTabId = ref.watch(
      workspaceProvider.select((state) => state.activeTabId),
    );
    final currentView = useState<String>('home');

    useEffect(() {
      workspaceNotifier.initialize();
      return () => workspaceNotifier.dispose();
    }, [workspaceNotifier]);

    // Switch between home and document view
    useEffect(() {
      if (activeTabId != null) {
        currentView.value = 'document';
      } else {
        currentView.value = 'home';
      }
      return null;
    }, [activeTabId]);

    final scrollController = useScrollController();
    final horizontalScrollController = useScrollController();

    // Scroll listener: delegates to active doc's onScrollChanged
    useEffect(() {
      void listener() async {
        final id = ref.read(workspaceProvider.select((s) => s.activeTabId));
        if (id != null) {
          await ref
              .read(pdfReaderProvider(id).notifier)
              .onScrollChanged(
                scrollController,
                View.of(context).devicePixelRatio,
              );
        }
      }

      scrollController.addListener(listener);
      return () => scrollController.removeListener(listener);
    }, [scrollController]);

    final filePath = activeTabId != null
        ? ref.watch(pdfReaderProvider(activeTabId).select((s) => s.filePath))
        : null;
    final isLoading = activeTabId != null
        ? ref.watch(pdfReaderProvider(activeTabId).select((s) => s.isLoading))
        : false;
    final outline = activeTabId != null
        ? ref.watch(pdfReaderProvider(activeTabId).select((s) => s.outline))
        : <OutlineItem>[];
    final isOutlinePanelOpen = activeTabId != null
        ? ref.watch(
            pdfReaderProvider(activeTabId).select((s) => s.isOutlinePanelOpen),
          )
        : false;

    final isDocumentView =
        currentView.value == 'document' && activeTabId != null;

    Widget mainContent;
    if (isLoading) {
      mainContent = _buildLoadingView();
    } else if (isDocumentView) {
      mainContent = _buildDocumentView(
        context,
        ref,
        activeTabId,
        scrollController,
        horizontalScrollController,
        outline,
        isOutlinePanelOpen,
        filePath,
      );
    } else {
      mainContent = _buildHomePage(context, workspaceNotifier);
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: Row(
        children: [
          _buildSidebar(context, currentView, workspaceNotifier),
          Expanded(
            child: Column(
              children: [
                _buildHeader(context, ref, workspaceNotifier, scrollController),
                Expanded(child: mainContent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Loading View ──────────────────────────────────────────────────────

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(accentBlue),
            ),
          ),
          SizedBox(height: 16),
          Text(
            '加载中...',
            style: TextStyle(
              fontSize: 14,
              color: textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Sidebar ───────────────────────────────────────────────────────────

  Widget _buildSidebar(
    BuildContext context,
    ValueNotifier<String> currentView,
    WorkspaceNotifier workspaceNotifier,
  ) {
    return Container(
      width: 64,
      decoration: const BoxDecoration(
        color: white,
        border: Border(right: BorderSide(color: borderColor)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accentBlue,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: accentBlue.withAlpha(50),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.picture_as_pdf, color: white, size: 22),
          ),
          const SizedBox(height: 32),
          SidebarButton(
            icon: Icons.history,
            tooltip: '历史记录',
            isActive: currentView.value == 'home',
            onTap: () => workspaceNotifier.goHome(),
          ),
          const SizedBox(height: 4),
          SidebarButton(
            icon: Icons.folder_open,
            tooltip: '打开文件',
            isActive: false,
            onTap: () async => await workspaceNotifier.openPdf(
              View.of(context).devicePixelRatio,
            ),
          ),
          const SizedBox(height: 16),
          Container(width: 32, height: 1, color: const Color(0xFFE2E8F0)),
          const SizedBox(height: 16),
          SidebarButton(
            icon: Icons.settings_outlined,
            tooltip: '设置',
            isActive: false,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  // ─── Header / Tab Bar ──────────────────────────────────────────────────

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    WorkspaceNotifier workspaceNotifier,
    ScrollController scrollController,
  ) {
    final openTabs = ref.watch(
      workspaceProvider.select((state) => state.openTabs),
    );
    final activeTabId = ref.watch(
      workspaceProvider.select((state) => state.activeTabId),
    );

    // useEffect(() {
    //   final tabCount = openTabs.length;
    //   if (tabCount == 0) {
    //     windowManager.setMinimumSize(const Size(600, 600));
    //   } else {
    //     final minWidth = tabCount * 52.0 + 600;
    //     windowManager.setMinimumSize(Size(minWidth, 600));
    //   }
    //   return null;
    // }, [openTabs.length]);

    return GestureDetector(
      onPanStart: (details) => windowManager.startDragging(),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.blue[50],
          // border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: Row(
          children: [
            if (openTabs.isNotEmpty) ...[
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 0),
                        child: _buildTabListView(
                          context,
                          ref,
                          workspaceNotifier,
                          openTabs,
                          activeTabId,
                          scrollController,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _buildAddTabButton(context, workspaceNotifier),
                  ],
                ),
              ),
            ] else ...[
              const Padding(
                padding: EdgeInsets.only(left: 16),
                child: Text(
                  'PDF Studio',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ),
              const Spacer(),
            ],
            const SizedBox(width: 4),
            // Container(width: 1, height: 20, color:  Colors.grey[300]),
            // const SizedBox(width: 8),
            WindowCaptionButton.minimize(
              onPressed: () => windowManager.minimize(),
            ),
            WindowCaptionButton.maximize(
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
            ),
            WindowCaptionButton.close(onPressed: () => windowManager.close()),
          ],
        ),
      ),
    );
  }

  Widget _buildTabListView(
    BuildContext context,
    WidgetRef ref,
    WorkspaceNotifier workspaceNotifier,
    List<TabInfo> openTabs,
    String? activeTabId,
    ScrollController scrollController,
  ) {
    final tabScrollController = useScrollController();
    final tabWidth = (200.0 - (openTabs.length - 1) * 10).clamp(100.0, 200.0);
    final activeIndex = openTabs.indexWhere((t) => t.fileHash == activeTabId);

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && tabScrollController.hasClients) {
          final newOffset = (tabScrollController.offset + event.scrollDelta.dy)
              .clamp(0.0, tabScrollController.position.maxScrollExtent);
          tabScrollController.jumpTo(newOffset);
        }
      },
      child: ListView(
        shrinkWrap: true,
        controller: tabScrollController,
        scrollDirection: Axis.horizontal,
        children: List.generate(openTabs.length, (i) {
          final tab = openTabs[i];
          final showRightDivider = i != activeIndex && i + 1 != activeIndex;
          return SizedBox(
            width: tabWidth,
            child: DocumentTab(
              fileName: tab.fileName,
              isActive: tab.fileHash == activeTabId,
              showRightDivider: showRightDivider,
              onTap: () => _switchToTab(ref, tab.fileHash, scrollController),
              onClose: () => workspaceNotifier.closeTab(tab.fileHash),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildAddTabButton(
    BuildContext context,
    WorkspaceNotifier workspaceNotifier,
  ) {
    return Tooltip(
      message: '新建文档',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async => await workspaceNotifier.openPdf(
            View.of(context).devicePixelRatio,
          ),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: const Icon(Icons.add, size: 18, color: textSecondary),
          ),
        ),
      ),
    );
  }

  void _switchToTab(
    WidgetRef ref,
    String fileHash,
    ScrollController scrollController,
  ) {
    final activeTabId = ref.read(
      workspaceProvider.select((s) => s.activeTabId),
    );
    if (activeTabId == fileHash) return;

    // Save scroll offset of current tab
    if (activeTabId != null && scrollController.hasClients) {
      ref
          .read(pdfReaderProvider(activeTabId).notifier)
          .saveScrollOffset(scrollController.offset);
    }

    ref.read(workspaceProvider.notifier).switchToTab(fileHash);

    // Restore scroll offset of new tab
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final saved = ref.read(pdfReaderProvider(fileHash)).savedScrollOffset;
      if (saved > 0 && scrollController.hasClients) {
        scrollController.jumpTo(saved);
      }
    });
  }

  // ─── Home Page ─────────────────────────────────────────────────────────

  Widget _buildHomePage(
    BuildContext context,
    WorkspaceNotifier workspaceNotifier,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '欢迎回来',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '今天你想阅读什么文件？',
                      style: TextStyle(fontSize: 14, color: textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
              LayoutBuilder(
                builder: (context, constraints) {
                  const cardHeight = 290.0;
                  return Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: [
                      SizedBox(
                        height: cardHeight,
                        child: _buildNewDocumentCard(workspaceNotifier),
                      ),
                      ...mockHistory.map(
                        (doc) => SizedBox(
                          height: cardHeight,
                          child: HistoryDocumentCard(
                            notifier: workspaceNotifier,
                            doc: doc,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNewDocumentCard(WorkspaceNotifier workspaceNotifier) {
    return NewDocumentCard(notifier: workspaceNotifier);
  }

  // ─── Document View ─────────────────────────────────────────────────────

  Widget _buildDocumentView(
    BuildContext context,
    WidgetRef ref,
    String activeTabId,
    ScrollController scrollController,
    ScrollController horizontalScrollController,
    List<OutlineItem> outline,
    bool isOutlinePanelOpen,
    String? filePath,
  ) {
    return Column(
      children: [
        _buildToolbar(
          context,
          ref,
          activeTabId,
          scrollController,
          horizontalScrollController,
          outline,
          isOutlinePanelOpen,
        ),
        Expanded(
          child: Stack(
            children: [
              _buildBody(
                context,
                ref,
                activeTabId,
                scrollController,
                horizontalScrollController,
              ),
              if (outline.isNotEmpty && isOutlinePanelOpen)
                _buildOutlinePanel(context, ref, activeTabId, scrollController),
              if (filePath != null)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: PageIndicator(activeTabId: activeTabId),
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
    );
  }

  // ─── Toolbar ────────────────────────────────────────────────────────────

  Widget _buildToolbar(
    BuildContext context,
    WidgetRef ref,
    String activeTabId,
    ScrollController scrollController,
    ScrollController horizontalScrollController,
    List<OutlineItem> outline,
    bool isOutlinePanelOpen,
  ) {
    final notifier = ref.read(pdfReaderProvider(activeTabId).notifier);

    final currentPage = ref.watch(
      pdfReaderProvider(activeTabId).select((state) => state.currentPage),
    );
    final totalPages = ref.watch(
      pdfReaderProvider(activeTabId).select((state) => state.totalPages),
    );
    final globalScale = ref.watch(
      pdfReaderProvider(activeTabId).select((state) => state.globalScale),
    );
    // final screenWidth = MediaQuery.of(context).size.width;
    final pdfViewWidth = MediaQuery.of(context).size.width - 64;
    final devicePixelRatio = View.of(context).devicePixelRatio;
    final originalPagesMaxWidth = ref.watch(
      pdfReaderProvider(activeTabId).select((s) => s.originalPagesMaxWidth),
    );
    final currentMaxWidth =
        originalPagesMaxWidth * globalScale / devicePixelRatio;
    // final isSelectionMode = ref.watch(
    //   pdfReaderProvider(activeTabId).select((state) => state.isSelectionMode),
    // );

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: white,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          if (outline.isNotEmpty)
            _toolbarIconButton(
              icon: Icons.toc,
              tooltip: isOutlinePanelOpen ? '关闭目录' : '打开目录',
              isActive: isOutlinePanelOpen,
              onTap: notifier.toggleOutlinePanel,
            ),
          if (outline.isNotEmpty) const SizedBox(width: 8),
          if (outline.isNotEmpty)
            Container(width: 1, height: 24, color: const Color(0xFFE2E8F0)),
          const SizedBox(width: 8),
          _toolbarIconButton(
            icon: Icons.chevron_left,
            tooltip: '上一页',
            onTap: currentPage > 0
                ? () => notifier.jumpToPage(currentPage - 1, scrollController)
                : null,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${currentPage + 1} / $totalPages',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          _toolbarIconButton(
            icon: Icons.chevron_right,
            tooltip: '下一页',
            onTap: currentPage < totalPages - 1
                ? () => notifier.jumpToPage(currentPage + 1, scrollController)
                : null,
          ),

          const Spacer(),

          _toolbarIconButton(
            icon: Icons.zoom_out,
            tooltip: '缩小',
            onTap: () => notifier.adjustZoom(
              -0.1,
              scrollController,
              devicePixelRatio,
              pdfViewWidth,
              currentMaxWidth,
              horizontalScrollController,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${(globalScale * 100).round()}%',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          _toolbarIconButton(
            icon: Icons.zoom_in,
            tooltip: '放大',
            onTap: () => notifier.adjustZoom(
              0.1,
              scrollController,
              devicePixelRatio,
              pdfViewWidth,
              currentMaxWidth,
              horizontalScrollController,
            ),
          ),

          Container(width: 1, height: 24, color: const Color(0xFFE2E8F0)),
          const SizedBox(width: 4),

          _toolbarIconButton(
            icon: Icons.dashboard_outlined,
            tooltip: '布局',
            onTap: () {},
          ),

          const Spacer(),

          // _toolbarIconButton(
          //   icon: Icons.text_fields,
          //   tooltip: isSelectionMode ? '退出选择' : '文本选择',
          //   isActive: isSelectionMode,
          //   onTap: notifier.toggleSelectionMode,
          // ),
          const SizedBox(width: 4),
          _toolbarActionButton(
            icon: Icons.edit_outlined,
            label: '编辑',
            onTap: () {},
          ),
          const SizedBox(width: 4),
          _toolbarIconButton(
            icon: Icons.bookmark_outline,
            tooltip: '书签',
            onTap: () {},
          ),
          _toolbarIconButton(
            icon: Icons.share_outlined,
            tooltip: '分享',
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _toolbarIconButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onTap,
    bool isActive = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? accentBlueLight : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isActive ? accentBlue : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _toolbarActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: accentBlue,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: accentBlue.withAlpha(40),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Body (PDF content) ─────────────────────────────────────────────────

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    String activeTabId,
    ScrollController scrollController,
    ScrollController horizontalScrollController,
  ) {
    final notifier = ref.read(pdfReaderProvider(activeTabId).notifier);

    final errorMessage = ref.watch(
      pdfReaderProvider(activeTabId).select((state) => state.errorMessage),
    );
    final pdfSendPort = ref.watch(
      pdfReaderProvider(activeTabId).select((state) => state.pdfSendPort),
    );
    final originalPagesMaxWidth = ref.watch(
      pdfReaderProvider(
        activeTabId,
      ).select((state) => state.originalPagesMaxWidth),
    );
    final globalScale = ref.watch(
      pdfReaderProvider(activeTabId).select((state) => state.globalScale),
    );
    final isCtrlPressed = ref.watch(
      pdfReaderProvider(activeTabId).select((state) => state.isCtrlPressed),
    );

    final totalPages = ref.watch(
      pdfReaderProvider(activeTabId).select((state) => state.totalPages),
    );
    final fileHash = ref.watch(
      pdfReaderProvider(activeTabId).select((state) => state.fileHash),
    );
    final pageHeights = ref.watch(
      pdfReaderProvider(
        activeTabId,
      ).select((state) => state.pageOriginalHeights),
    );

    if (errorMessage != null) {
      return Center(
        child: Text(errorMessage, style: const TextStyle(color: Colors.red)),
      );
    }
    if (pdfSendPort == null) {
      return const Center(child: Text("请打开 PDF 文件"));
    }

    final pdfViewWidth = MediaQuery.of(context).size.width - 64;

    final devicePixelRatio = View.of(context).devicePixelRatio;
    final currentMaxWidth =
        originalPagesMaxWidth * globalScale / devicePixelRatio;

    final pdfView = _buildPdfView(
      context,
      notifier,
      isCtrlPressed,
      totalPages,
      fileHash,
      scrollController,
      horizontalScrollController,
      pageHeights,
      currentMaxWidth,
      globalScale,
    );

    return Stack(
      children: [
        Listener(
          onPointerSignal: (event) => notifier.handlePointerSignal(
            event,
            scrollController,
            horizontalScrollController,
            devicePixelRatio,
            pdfViewWidth,
            currentMaxWidth,
          ),
          child: pdfView,
        ),
        Positioned.fill(
          child: _SelectionGestureLayer(
            notifier: notifier,
            scrollController: scrollController,
            horizontalScrollController: horizontalScrollController,
            pageHeights: pageHeights,
            totalPages: totalPages,
            globalScale: globalScale,
            devicePixelRatio: devicePixelRatio,
            currentMaxWidth: currentMaxWidth,
          ),
        ),
      ],
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
    Map<int, double>? pageHeights,
    double currentMaxWidth,
    double globalScale,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;

    final heightsOnDevice = List<double>.generate(totalPages * 2, (index) {
      if (index.isOdd) {
        return 10;
      }
      final pageIndex = index ~/ 2;
      if (pageHeights != null && pageHeights[pageIndex] != null) {
        return pageHeights[pageIndex]! * globalScale;
      } else {
        return 842 / View.of(context).devicePixelRatio * globalScale;
      }
    });

    return Container(
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
            width: math.max(currentMaxWidth, screenWidth - 64),
            child: ScrollConfiguration(
              behavior: const ScrollBehavior().copyWith(scrollbars: false),
              child: CustomScrollView(
                controller: scrollController,
                physics: (isCtrlPressed)
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
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Outline Panel ──────────────────────────────────────────────────────

  Widget _buildOutlinePanel(
    BuildContext context,
    WidgetRef ref,
    String activeTabId,
    ScrollController scrollController,
  ) {
    final notifier = ref.read(pdfReaderProvider(activeTabId).notifier);

    final outline = ref.watch(
      pdfReaderProvider(activeTabId).select((state) => state.outline),
    );
    final expandedIds = ref.watch(
      pdfReaderProvider(
        activeTabId,
      ).select((state) => state.expandedOutlineIds),
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

// ─── Selection Gesture Layer ─────────────────────────────────────────────

class _SelectionGestureLayer extends HookConsumerWidget {
  final PdfReaderNotifier notifier;
  final ScrollController scrollController;
  final ScrollController horizontalScrollController;
  final Map<int, double>? pageHeights;
  final int totalPages;
  final double globalScale;
  final double devicePixelRatio;
  final double currentMaxWidth;

  const _SelectionGestureLayer({
    required this.notifier,
    required this.scrollController,
    required this.horizontalScrollController,
    required this.pageHeights,
    required this.totalPages,
    required this.globalScale,
    required this.devicePixelRatio,
    required this.currentMaxWidth,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTabId = ref.watch(
      workspaceProvider.select((s) => s.activeTabId),
    );
    final isHoveringText = activeTabId != null
        ? ref.watch(
            pdfReaderProvider(activeTabId).select((s) => s.isHoveringText),
          )
        : false;

    // final isSelecting = useState(false);
    final lastContentY = useState(0.0);

    // Precompute scaled page heights and top offsets
    final scaledHeights = useMemoized(() {
      if (pageHeights == null) return <double>[];
      return List<double>.generate(totalPages, (i) {
        return (pageHeights![i] ?? 842) * globalScale;
      });
    }, [pageHeights, totalPages, globalScale]);

    final pageTopOffsets = useMemoized(() {
      final offsets = <double>[];
      double acc = 0;
      for (int i = 0; i < totalPages; i++) {
        offsets.add(acc);
        acc +=
            (scaledHeights.length > i ? scaledHeights[i] : 842 * globalScale) +
            10;
      }
      return offsets;
    }, [scaledHeights]);

    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = math.max(currentMaxWidth, screenWidth - 64);

    final pageSizesForFile = useMemoized(() {
      final id = ref.read(workspaceProvider.select((s) => s.activeTabId));
      if (id == null) return null;
      final state = ref.read(pdfReaderProvider(id));
      final hash = state.fileHash;
      if (hash == null) return null;
      return state.docRawPageSizes[hash];
    }, [activeTabId]);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => notifier.clearSelection(),
      onPanStart: isHoveringText
          ? (details) {
              // isSelecting.value = true;
              final contentY =
                  details.localPosition.dy + scrollController.offset;
              lastContentY.value = contentY;
              final result = _mapToPage(
                contentY,
                details.localPosition.dx + horizontalScrollController.offset,
                pageTopOffsets,
                scaledHeights,
                maxWidth,
                pageSizesForFile,
              );
              if (result != null) {
                notifier.handleSelectionStart(
                  result.pageIndex,
                  result.localPosition,
                  devicePixelRatio,
                );
              }
            }
          : null,
      onPanUpdate: (details) {
        final contentY = details.localPosition.dy + scrollController.offset;
        final contentX =
            details.localPosition.dx + horizontalScrollController.offset;
        final goingDown = contentY >= lastContentY.value;
        lastContentY.value = contentY;

        var result = _mapToPage(
          contentY,
          contentX,
          pageTopOffsets,
          scaledHeights,
          maxWidth,
          pageSizesForFile,
        );
        result ??= _snapToNearestPage(
          contentY,
          contentX,
          pageTopOffsets,
          scaledHeights,
          maxWidth,
          pageSizesForFile,
          goingDown,
        );
        if (result != null) {
          notifier.handleSelectionUpdate(
            result.pageIndex,
            result.localPosition,
            devicePixelRatio,
          );
        }
      },
      onPanEnd: (_) {
        notifier.handleSelectionEnd();
      },
    );
  }

  ({int pageIndex, Offset localPosition})? _mapToPage(
    double contentY,
    double contentX,
    List<double> tops,
    List<double> heights,
    double maxWidth,
    Map<int, List<int>>? pageSizesForFile,
  ) {
    for (int i = 0; i < tops.length && i < heights.length; i++) {
      final top = tops[i];
      final h = heights[i];
      if (contentY >= top && contentY < top + h) {
        final adjustedX = _adjustContentX(
          contentX,
          i,
          maxWidth,
          pageSizesForFile,
        );
        return (pageIndex: i, localPosition: Offset(adjustedX, contentY - top));
      }
    }
    return null;
  }

  ({int pageIndex, Offset localPosition})? _snapToNearestPage(
    double contentY,
    double contentX,
    List<double> tops,
    List<double> heights,
    double maxWidth,
    Map<int, List<int>>? pageSizesForFile,
    bool goingDown,
  ) {
    for (int i = 0; i < tops.length - 1 && i < heights.length; i++) {
      final pageBottom = tops[i] + heights[i];
      final nextPageTop = tops[i + 1];
      if (contentY >= pageBottom && contentY < nextPageTop) {
        if (goingDown) {
          final adjustedX = _adjustContentX(
            contentX,
            i + 1,
            maxWidth,
            pageSizesForFile,
          );
          return (pageIndex: i + 1, localPosition: Offset(adjustedX, 1));
        } else {
          final adjustedX = _adjustContentX(
            contentX,
            i,
            maxWidth,
            pageSizesForFile,
          );
          return (
            pageIndex: i,
            localPosition: Offset(adjustedX, heights[i] - 1),
          );
        }
      }
    }
    // Snap to first or last page if beyond all pages
    if (tops.isNotEmpty && contentY < tops.first) {
      final adjustedX = _adjustContentX(
        contentX,
        0,
        maxWidth,
        pageSizesForFile,
      );
      return (pageIndex: 0, localPosition: Offset(adjustedX, 1));
    }
    if (tops.isNotEmpty &&
        heights.isNotEmpty &&
        contentY >= tops.last + heights.last) {
      final lastIdx = tops.length - 1;
      final adjustedX = _adjustContentX(
        contentX,
        lastIdx,
        maxWidth,
        pageSizesForFile,
      );
      return (
        pageIndex: lastIdx,
        localPosition: Offset(adjustedX, heights[lastIdx] - 1),
      );
    }
    return null;
  }

  double _adjustContentX(
    double contentX,
    int pageIndex,
    double maxWidth,
    Map<int, List<int>>? pageSizesForFile,
  ) {
    final rawSize = pageSizesForFile?[pageIndex];
    if (rawSize == null || rawSize.length < 2) return contentX;
    final pageWidth = rawSize[0] / devicePixelRatio * globalScale;
    final leftPadding = (maxWidth - pageWidth) / 2;
    return contentX - leftPadding;
  }
}
