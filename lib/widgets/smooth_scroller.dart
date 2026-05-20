import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return SmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class SmoothScrollPosition extends ScrollPositionWithSingleContext {
  SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels = 0,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  Ticker? _ticker;

  double _velocity = 0;

  Duration? _lastTimeStamp;

  static const double friction = 0.90;

  static const double sensitivity = 1.05;

  // static const double minVelocity = 200;

  static const double maxVelocity = 3000;

  @override
  void pointerScroll(double delta) {
    if (delta == 0) return;

    // 累积速度（核心）
    _velocity += delta * 20 * sensitivity;

    _velocity = _velocity.clamp(-maxVelocity, maxVelocity);

    // 启动 ticker
    _ticker ??= context.vsync.createTicker(_tick);

    if (!_ticker!.isActive) {
      _lastTimeStamp = null;
      didStartScroll();
      _ticker!.start();
    }
  }

  void _tick(Duration timestamp) {
    if (_lastTimeStamp == null) {
      _lastTimeStamp = timestamp;
      return;
    }

    final dt = (timestamp - _lastTimeStamp!).inMicroseconds / 1e6;

    _lastTimeStamp = timestamp;

    // velocity integration
    double delta = _velocity * dt;

    if (delta.abs() < 0.1) {
      _ticker?.stop();
      _velocity = 0;
      didEndScroll();
      return;
    }

    double target = pixels + delta;

    // 边界处理
    target = target.clamp(minScrollExtent, maxScrollExtent);

    final oldPixels = pixels;

    forcePixels(target);
    didUpdateScrollPositionBy(pixels - oldPixels);

    // friction decay
    _velocity *= friction;

  }

  @override
  void beginActivity(ScrollActivity? newActivity) {
    // 用户拖拽时停止惯性
    if (newActivity is! IdleScrollActivity) {
      _ticker?.stop();
    }

    super.beginActivity(newActivity);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }
}

/// -------------------------------
/// Hook
/// -------------------------------
class _ScrollControllerHook extends Hook<ScrollController> {
  const _ScrollControllerHook({
    required this.initialScrollOffset,
    required this.keepScrollOffset,
    this.debugLabel,
    super.keys,
  });

  final double initialScrollOffset;
  final bool keepScrollOffset;
  final String? debugLabel;

  @override
  HookState<ScrollController, Hook<ScrollController>> createState() =>
      _ScrollControllerHookState();
}

class _ScrollControllerHookState
    extends HookState<ScrollController, _ScrollControllerHook> {
  late final controller = SmoothScrollController(
    initialScrollOffset: hook.initialScrollOffset,
    keepScrollOffset: hook.keepScrollOffset,
    debugLabel: hook.debugLabel,
  );

  @override
  ScrollController build(BuildContext context) => controller;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

/// -------------------------------
/// Hook API
/// -------------------------------
ScrollController useSmoothScrollController({
  double initialScrollOffset = 0,
  bool keepScrollOffset = true,
  String? debugLabel,
  List<Object?>? keys,
}) {
  return use(
    _ScrollControllerHook(
      initialScrollOffset: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      debugLabel: debugLabel,
      keys: keys,
    ),
  );
}
