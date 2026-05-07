import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class VariedExtentList extends SliverMultiBoxAdaptorWidget {
  final List<double> itemExtents;

  const VariedExtentList({
    super.key,
    required super.delegate,
    required this.itemExtents,
  });

  @override
  RenderSliverVariedExtentList createRenderObject(BuildContext context) {
    final element = context as SliverMultiBoxAdaptorElement;

    return RenderSliverVariedExtentList(
      childManager: element,
      itemExtentBuilder: (index, _) {
        if (index < 0 || index >= itemExtents.length) {
          return null;
        }
        return itemExtents[index];
      },
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderSliverVariedExtentList renderObject,
  ) {
    renderObject.itemExtentBuilder = (index, _) {
      if (index < 0 || index >= itemExtents.length) {
        return null;
      }
      return itemExtents[index];
    };
  }
}