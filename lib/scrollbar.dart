import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:unified_pdf_reader/providers/pdf_reader_provider.dart';

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
  final double minThumbHeight;

  CustomScrollbarNotifier({this.minThumbHeight = 40});

  @override
  CustomScrollbarState build() {
    // Listen to workspace changes to recalc thumb on tab switch
    ref.listen(workspaceProvider, (prev, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) => updateThumb());
    });

    return const CustomScrollbarState();
  }

  void initialize(ScrollController controller) {
    _controller = controller;
    controller.addListener(updateThumb);
    WidgetsBinding.instance.addPostFrameCallback((_) => updateThumb());
  }

  void dispose() {
    _controller?.removeListener(updateThumb);
    _controller = null;
  }

  void updateThumb() {
    final c = _controller;
    if (c == null || !c.hasClients) return;

    final activeTabId = ref.read(workspaceProvider).activeTabId;
    if (activeTabId == null) return;

    final pos = c.position;
    final viewport = pos.viewportDimension;
    final contentHeight =
        ref.read(pdfReaderProvider(activeTabId)).maxScaledPageSumHeight;
    final maxScroll = math.max(0.0, contentHeight - viewport);

    if (contentHeight <= viewport) {
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

  void handleDrag(DragUpdateDetails details) {
    final c = _controller;
    if (c == null || !c.hasClients) return;

    final activeTabId = ref.read(workspaceProvider).activeTabId;
    if (activeTabId == null) return;

    final pos = c.position;
    final viewport = pos.viewportDimension;
    final contentHeight =
        ref.read(pdfReaderProvider(activeTabId)).maxScaledPageSumHeight;
    final maxScroll = math.max(0.0, contentHeight - viewport);
    if (maxScroll <= 0) return;
    final ratio = contentHeight / viewport;

    final newOffset = c.offset + details.delta.dy * ratio;
    c.jumpTo(newOffset.clamp(0.0, maxScroll).toDouble());
  }
}

final customScrollbarProvider =
    NotifierProvider<CustomScrollbarNotifier, CustomScrollbarState>(
      CustomScrollbarNotifier.new,
    );

class CustomScrollbar extends HookConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(customScrollbarProvider.notifier);

    // Watch activeTabId changes and the active document's content height
    final activeTabId = ref.watch(workspaceProvider.select((s) => s.activeTabId));
    final maxContentHeight = activeTabId != null
        ? ref.watch(
            pdfReaderProvider(activeTabId)
                .select((s) => s.maxScaledPageSumHeight),
          )
        : 0.0;

    useEffect(() {
      notifier.initialize(controller);
      return () => notifier.dispose();
    }, [controller]);

    // Recalc thumb when the active document's content height becomes available
    // (e.g. after async fullInit completes) or changes (e.g. zoom).
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) => notifier.updateThumb());
      return null;
    }, [maxContentHeight]);

    final scrollbarState = ref.watch(customScrollbarProvider);

    if (!scrollbarState.hasContent) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (details) {
        ref.read(customScrollbarProvider.notifier).handleDrag(details);
      },
      child: Container(
        width: thickness + 6,
        color: Colors.transparent,
        alignment: Alignment.topRight,
        child: Container(
          margin: EdgeInsets.only(
            top: scrollbarState.thumbTop,
            right: marginRight,
          ),
          height: scrollbarState.thumbHeight,
          width: thickness,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.all(radius),
          ),
        ),
      ),
    );
  }
}
