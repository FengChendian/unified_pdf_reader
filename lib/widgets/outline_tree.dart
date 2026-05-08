import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../mupdf/mupdf.dart';

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

    void Function()? onTapHandler;
    if (hasChildren) {
      onTapHandler = () => onToggleExpand(id);
    } else if (item.page >= 0) {
      onTapHandler = () => onJumpToPage(item.page);
    }

    final double iconSize = isRoot ? 18.0 : 16.0;
    final double fontSize = isRoot ? 13.0 : 12.0;
    final FontWeight fontWeight = isRoot ? FontWeight.w500 : FontWeight.normal;

    final EdgeInsetsGeometry containerPadding = isRoot
        ? EdgeInsets.zero
        : EdgeInsets.only(left: 12 + (depth - 1) * 16.0);

    Widget? childrenTreeWidget;
    if (hasChildren && isExpanded) {
      childrenTreeWidget = OutlineTreeWidget(
        items: item.children,
        expandedIds: expandedIds,
        onToggleExpand: onToggleExpand,
        onJumpToPage: onJumpToPage,
        depth: depth + 1,
      );

      if (isRoot) {
        childrenTreeWidget = Padding(
          padding: const EdgeInsets.only(left: 24),
          child: childrenTreeWidget,
        );
      }
    }

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
        if (childrenTreeWidget != null) childrenTreeWidget,
      ],
    );
  }
}
