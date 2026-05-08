import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../cache_list.dart';
import '../constants/app_colors.dart';
import '../constants/mock_data.dart';
import '../mupdf/mupdf.dart';
import '../providers/pdf_reader_provider.dart';
import '../scrollbar.dart';
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
    final filePath = ref.watch(
      pdfReaderProvider.select((state) => state.filePath),
    );
    final notifier = ref.read(pdfReaderProvider.notifier);

    final currentView = useState<String>('home');

    useEffect(() {
      notifier.initialize();
      return () => notifier.dispose();
    }, [notifier]);

    // Switch to document view when a file is picked
    useEffect(() {
      if (filePath != null) {
        currentView.value = 'document';
      } else {
        currentView.value = 'home';
      }
      return null;
    }, [filePath]);

    final scrollController = useScrollController();
    final horizontalScrollController = useScrollController();

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
    final isLoading = ref.watch(
      pdfReaderProvider.select((state) => state.isLoading),
    );

    final isDocumentView = currentView.value == 'document' && filePath != null;

    Widget mainContent;
    if (isLoading) {
      mainContent = _buildLoadingView();
    } else if (isDocumentView) {
      mainContent = _buildDocumentView(
        context,
        ref,
        notifier,
        scrollController,
        horizontalScrollController,
        outline,
        isOutlinePanelOpen,
        filePath,
      );
    } else {
      mainContent = _buildHomePage(context, notifier);
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: Row(
        children: [
          // Left sidebar
          _buildSidebar(context, currentView, notifier),
          // Main content area
          Expanded(
            child: Column(
              children: [
                _buildHeader(context, filePath, notifier),
                Expanded(child: mainContent),
              ],
            ),
          ),
          // Right mini panel (document view only)
          // if (isDocumentView) _buildRightMiniPanel(),
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
    PdfReaderNotifier notifier,
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
          // App icon
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
          // History / Home button
          SidebarButton(
            icon: Icons.history,
            tooltip: '历史记录',
            isActive: currentView.value == 'home',
            onTap: () => currentView.value = 'home',
          ),
          const SizedBox(height: 4),
          // Folder open button
          SidebarButton(
            icon: Icons.folder_open,
            tooltip: '打开文件',
            isActive: false,
            onTap: () async =>
                await notifier.pickPdf(View.of(context).devicePixelRatio),
          ),
          const SizedBox(height: 16),
          // Divider
          Container(width: 32, height: 1, color: const Color(0xFFE2E8F0)),
          const SizedBox(height: 16),
          // Settings button
          SidebarButton(
            icon: Icons.settings_outlined,
            tooltip: '设置',
            isActive: false,
            onTap: () {}, // No backend
          ),
        ],
      ),
    );
  }

  // ─── Header / Tab Bar ──────────────────────────────────────────────────

  Widget _buildHeader(
    BuildContext context,
    String? filePath,
    PdfReaderNotifier notifier,
  ) {
    return GestureDetector(
      onPanStart: (details) => windowManager.startDragging(),
      child: Container(
        height: 44,
        decoration: const BoxDecoration(
          color: white,
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: Row(
          children: [
            if (filePath != null) ...[
              // Document tab + add button
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, top: 6),
                  child: Row(
                    children: [
                      _buildTab(filePath, notifier),
                      const SizedBox(width: 4),
                      _buildAddTabButton(context, notifier),
                    ],
                  ),
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
            // Window caption buttons
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

  Widget _buildTab(String filePath, PdfReaderNotifier notifier) {
    return DocumentTab(filePath: filePath, notifier: notifier);
  }

  Widget _buildAddTabButton(BuildContext context, PdfReaderNotifier notifier) {
    return Tooltip(
      message: '新建文档',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async =>
            await notifier.pickPdf(View.of(context).devicePixelRatio),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: const Icon(Icons.add, size: 16, color: textSecondary),
        ),
      ),
    );
  }

  // ─── Home Page ─────────────────────────────────────────────────────────

  Widget _buildHomePage(BuildContext context, PdfReaderNotifier notifier) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 10), // 2 + 8
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
              // Card grid
              LayoutBuilder(
                builder: (context, constraints) {
                  const cardHeight = 290.0;
                  return Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: [
                      SizedBox(
                        height: cardHeight,
                        child: _buildNewDocumentCard(notifier),
                      ),
                      ...mockHistory.map(
                        (doc) => SizedBox(
                          height: cardHeight,
                          child: HistoryDocumentCard(
                            notifier: notifier,
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

  Widget _buildNewDocumentCard(PdfReaderNotifier notifier) {
    return NewDocumentCard(notifier: notifier);
  }

  // ─── Document View ─────────────────────────────────────────────────────

  Widget _buildDocumentView(
    BuildContext context,
    WidgetRef ref,
    PdfReaderNotifier notifier,
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
          notifier,
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
                notifier,
                scrollController,
                horizontalScrollController,
              ),
              if (outline.isNotEmpty && isOutlinePanelOpen)
                _buildOutlinePanel(context, ref, notifier, scrollController),
              if (filePath != null)
                const Positioned(right: 16, bottom: 16, child: PageIndicator()),
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

  // ─── Toolbar (redesigned) ──────────────────────────────────────────────

  Widget _buildToolbar(
    BuildContext context,
    WidgetRef ref,
    PdfReaderNotifier notifier,
    ScrollController scrollController,
    ScrollController horizontalScrollController,
    List<OutlineItem> outline,
    bool isOutlinePanelOpen,
  ) {
    final currentPage = ref.watch(
      pdfReaderProvider.select((state) => state.currentPage),
    );
    final totalPages = ref.watch(
      pdfReaderProvider.select((state) => state.totalPages),
    );
    final globalScale = ref.watch(
      pdfReaderProvider.select((state) => state.globalScale),
    );

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: white,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          // Left: sidebar toggle + page nav
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

          // Center: zoom controls
          _toolbarIconButton(
            icon: Icons.zoom_out,
            tooltip: '缩小',
            onTap: () => notifier.adjustZoom(
              -0.1,
              scrollController,
              horizontalScrollController,
            ),
          ),
          Container(
            width: 56,
            alignment: Alignment.center,
            child: Text(
              '${(globalScale * 100).round()}%',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          _toolbarIconButton(
            icon: Icons.zoom_in,
            tooltip: '放大',
            onTap: () => notifier.adjustZoom(
              0.1,
              scrollController,
              horizontalScrollController,
            ),
          ),

          Container(width: 1, height: 24, color: const Color(0xFFE2E8F0)),
          const SizedBox(width: 4),

          _toolbarIconButton(
            icon: Icons.dashboard_outlined,
            tooltip: '布局',
            onTap: () {}, // Placeholder
          ),

          const Spacer(),

          // Right: action buttons
          _toolbarActionButton(
            icon: Icons.edit_outlined,
            label: '编辑',
            onTap: () {}, // No backend
          ),
          const SizedBox(width: 4),
          _toolbarIconButton(
            icon: Icons.bookmark_outline,
            tooltip: '书签',
            onTap: () {}, // No backend
          ),
          _toolbarIconButton(
            icon: Icons.share_outlined,
            tooltip: '分享',
            onTap: () {}, // No backend
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

  // ─── Right Mini Panel ──────────────────────────────────────────────────

  Widget _buildRightMiniPanel() {
    return Container(
      width: 48,
      decoration: const BoxDecoration(
        color: white,
        border: Border(left: BorderSide(color: borderColor)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {}, // No backend
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              child: const Icon(Icons.menu, size: 18, color: textSecondary),
            ),
          ),
          const SizedBox(height: 16),
          Container(width: 24, height: 1, color: const Color(0xFFE2E8F0)),
          const SizedBox(height: 16),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF22C55E),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Body (PDF content) — UNCHANGED ────────────────────────────────────

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    PdfReaderNotifier notifier,
    ScrollController scrollController,
    ScrollController horizontalScrollController,
  ) {
    final errorMessage = ref.watch(
      pdfReaderProvider.select((state) => state.errorMessage),
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
    if (pdfSendPort == null) {
      return const Center(child: Text("请打开 PDF 文件"));
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final devicePixelRatio = View.of(context).devicePixelRatio;
    final currentMaxWidth =
        originalPagesMaxWidth * globalScale / devicePixelRatio;

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
            width: math.max(currentMaxWidth, screenWidth),
            child: ScrollConfiguration(
              behavior: const ScrollBehavior().copyWith(scrollbars: false),
              child: CustomScrollView(
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
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Outline Panel — UNCHANGED ─────────────────────────────────────────

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
