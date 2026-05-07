import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unified_pdf_reader/providers/pdf_reader_provider.dart';

/// 滚动条总滚动范围 Provider
/// 当 pageHeights 或 globalScale 变化时会自动重算
final scrollbarMaxExtentProvider = Provider<double>((ref) {
  final pageHeights = ref.watch(
    pdfReaderProvider.select((s) => s.pageOriginalHeights),
  );
  final scale = ref.watch(
    pdfReaderProvider.select((s) => s.globalScale),
  );
  if (pageHeights.values.isEmpty) return 0.0;
  return pageHeights.values.fold<double>(0.0, (a, b) => a + b) * scale +
      pageHeights.length * 10.0;
});

/// 自定义滚动条状态
class CustomScrollbarState {
  final double thumbHeight;
  final double thumbTop;
  final bool hasContent;

  const CustomScrollbarState({
    this.thumbHeight = 40,
    this.thumbTop = 0,
    this.hasContent = false,
  });

  CustomScrollbarState copyWith({
    double? thumbHeight,
    double? thumbTop,
    bool? hasContent,
  }) {
    return CustomScrollbarState(
      thumbHeight: thumbHeight ?? this.thumbHeight,
      thumbTop: thumbTop ?? this.thumbTop,
      hasContent: hasContent ?? this.hasContent,
    );
  }
}

/// 自定义滚动条 Notifier
class CustomScrollbarNotifier extends Notifier<CustomScrollbarState> {
  ScrollController? _controller;
  final double thickness;
  final double minThumbHeight;

  CustomScrollbarNotifier({this.thickness = 6, this.minThumbHeight = 40});

  @override
  CustomScrollbarState build() {
    // 监听 pageHeights / globalScale 派生出的 maxScrollExtent
    // 任何一个变化都会自动触发滚动条拇指重算
    ref.listen<double>(scrollbarMaxExtentProvider, (previous, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateThumb());
    });

    return const CustomScrollbarState();
  }

  /// 初始化滚动控制器监听
  void initialize(ScrollController controller) {
    _controller = controller;
    controller.addListener(_updateThumb);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateThumb());
  }

  /// 切换滚动控制器
  void updateController(
    ScrollController? oldController,
    ScrollController? newController,
  ) {
    if (oldController == newController) return;
    if (oldController != null) {
      oldController.removeListener(_updateThumb);
    }
    _controller = newController;
    if (newController != null) {
      newController.addListener(_updateThumb);
      _updateThumb();
    }
  }

  /// 清理
  void dispose() {
    _controller?.removeListener(_updateThumb);
    _controller = null;
  }

  /// 更新滚动条拇指位置和大小
  void _updateThumb() {
    final c = _controller;
    if (c == null || !c.hasClients) return;

    final pos = c.position;
    final viewport = pos.viewportDimension;
    final maxScroll = ref.read(scrollbarMaxExtentProvider);

    final contentHeight = maxScroll + viewport;

    // 内容不足一屏，隐藏滚动条
    if (contentHeight <= viewport || maxScroll <= 0) {
      if (state.hasContent) {
        state = state.copyWith(hasContent: false);
      }
      return;
    }

    final rawThumb = viewport * viewport / contentHeight;
    final thumbHeight = math.max(minThumbHeight, rawThumb);
    final thumbTop = maxScroll > 0
        ? (c.offset / maxScroll) * (viewport - thumbHeight)
        : 0.0;

    if (!state.hasContent ||
        (state.thumbHeight - thumbHeight).abs() > 0.5 ||
        (state.thumbTop - thumbTop).abs() > 0.5) {
      state = state.copyWith(
        hasContent: true,
        thumbHeight: thumbHeight,
        thumbTop: thumbTop.clamp(0.0, viewport - thumbHeight),
      );
    }
  }

  /// 处理拖拽
  void handleDrag(DragUpdateDetails details) {
    final c = _controller;
    if (c == null || !c.hasClients) return;

    final pos = c.position;
    final viewport = pos.viewportDimension;
    final maxScroll = ref.read(scrollbarMaxExtentProvider);
    if (maxScroll <= 0) return;

    final contentHeight = maxScroll + viewport;
    final ratio = contentHeight / viewport;

    final newOffset = c.offset + details.delta.dy * ratio;
    c.jumpTo(newOffset.clamp(0.0, maxScroll));
  }
}

/// 滚动条 Provider
final customScrollbarProvider =
    NotifierProvider<CustomScrollbarNotifier, CustomScrollbarState>(
      CustomScrollbarNotifier.new,
    );

/// 自定义滚动条 Widget
class CustomScrollbar extends ConsumerStatefulWidget {
  final ScrollController controller;
  final double thickness;
  final Radius radius;
  final Color color;
  final double minThumbHeight;
  final double marginRight;

  const CustomScrollbar({
    super.key,
    required this.controller,
    this.thickness = 6,
    this.radius = const Radius.circular(3),
    this.color = const Color(0xFFB0B0B0),
    this.minThumbHeight = 40,
    this.marginRight = 0,
  });

  @override
  ConsumerState<CustomScrollbar> createState() => _CustomScrollbarState();
}

class _CustomScrollbarState extends ConsumerState<CustomScrollbar> {
  late CustomScrollbarNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(customScrollbarProvider.notifier);
    _notifier.initialize(widget.controller);
  }

  // @override
  // void didUpdateWidget(covariant CustomScrollbar oldWidget) {
  //   super.didUpdateWidget(oldWidget);
  //   if (oldWidget.controller != widget.controller) {
  //     _notifier.updateController(oldWidget.controller, widget.controller);
  //   }
  // }

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scrollbarState = ref.watch(customScrollbarProvider);

    if (!scrollbarState.hasContent) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (details) {
        ref.read(customScrollbarProvider.notifier).handleDrag(details);
      },
      child: Container(
        width: widget.thickness + 6,
        color: Colors.transparent,
        alignment: Alignment.topRight,
        child: Container(
          margin: EdgeInsets.only(
            top: scrollbarState.thumbTop,
            right: widget.marginRight,
          ),
          height: scrollbarState.thumbHeight,
          width: widget.thickness,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.all(widget.radius),
          ),
        ),
      ),
    );
  }
}
