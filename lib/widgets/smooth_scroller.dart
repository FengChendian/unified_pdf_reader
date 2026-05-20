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

  // 物理参数配置
  // 阻尼系数 (Drag)：表示 1 秒后剩余的速度比例。0.01 表示 1秒后几乎停下。值越大滑得越远。
  static const double dampling = 0.004;
  // 冲量敏感度：每次滚轮事件转化为速度的乘数。
  static const double impulseMultiplier = 20.0;
  // static const double maxVelocity = 4000;
  static final double _lnDrag = log(dampling);
  static final double _invLnDrag = 1.0 / _lnDrag; // 预计算倒数，变除法为乘法
  @override
  void pointerScroll(double delta) {
    if (delta == 0) return;

    // 1. 物理学：施加冲量 (Impulse)，瞬间改变当前动量 (Velocity)
    // 鼠标连续滚动时，冲量会不断叠加，形成非常跟手的加速感
    _velocity += delta * impulseMultiplier;
    // _velocity = _velocity.clamp(-maxVelocity, maxVelocity);

    // 启动物理引擎 (Ticker)
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

    if (dt == 0) return;

    if (_velocity.abs() < 1.0) {
      _stopSimulation();
      return;
    }

    // ----------------- 优化 2 & 3：用 exp 代替 pow，且只计算一次 -----------------
    // 利用数学公式：pow(drag, dt) 等价于 exp(dt * ln(drag))
    // 这一步直接拿到了本帧的衰减因子
    final double decay = exp(dt * _lnDrag);

    // 使用预计算的 _invLnDrag，彻底消除了帧循环中的 log 运算和除法运算
    double deltaOffset = _velocity * _invLnDrag * (decay - 1.0);

    double target = pixels + deltaOffset;
    target = target.clamp(minScrollExtent, maxScrollExtent);
    final oldPixels = pixels;

    forcePixels(target);
    didUpdateScrollPositionBy(pixels - oldPixels);

    if (pixels == oldPixels && deltaOffset.abs() > 1e-3) {
      _stopSimulation();
      return;
    }

    // 直接复用上面算好的 decay，原本需要二次计算的 pow 被消除了
    _velocity *= decay;
  }

  void _stopSimulation() {
    _ticker?.stop();
    _velocity = 0;
    didEndScroll();
  }

  @override
  void beginActivity(ScrollActivity? newActivity) {
    // 用户发生触摸拖拽等其他交互时，打断惯性
    if (newActivity is! IdleScrollActivity) {
      _stopSimulation();
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
