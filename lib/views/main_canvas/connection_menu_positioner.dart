import 'package:flutter/material.dart';

/// 接続線のコンテキストメニューを、**実際の高さを計測して**画面内に収める位置へ配置する。
///
/// 従来の実装はメニュー高さを推測値（260px）でハードコードしており、
/// 実際の高さ（約 320px）より小さかったため、画面下部で開いた際に
/// 「接続線を解除」が画面外にはみ出してタップできない問題があった。
///
/// 本ウィジェットは、子メニューのレイアウト後に [GlobalKey] で実際の高さを
/// 取得し、タップ位置（[screenPos]）の右下を基本に、画面からはみ出す場合は
/// 左上側に反転させて、最終的に画面内に収まるよう位置を補正する。
class ConnectionMenuPositioner extends StatefulWidget {
  final Offset screenPos;
  final double menuWidth;
  final double margin;
  final double initialLeft;
  final double initialTop;
  final Widget child;

  const ConnectionMenuPositioner({
    super.key,
    required this.screenPos,
    required this.menuWidth,
    required this.margin,
    required this.initialLeft,
    required this.initialTop,
    required this.child,
  });

  @override
  State<ConnectionMenuPositioner> createState() =>
      _ConnectionMenuPositionerState();
}

class _ConnectionMenuPositionerState extends State<ConnectionMenuPositioner> {
  final GlobalKey _menuKey = GlobalKey();
  double? _measuredHeight;

  /// 実際の高さ（未計測時は推測値）を返す。
  double get _height => _measuredHeight ?? 320.0;

  /// 画面内に収まるよう、タップ位置の右下 / 左上を切り替えて位置を計算する。
  (double left, double top) _computePosition(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = widget.menuWidth;
    final h = _height;
    final m = widget.margin;
    final sx = widget.screenPos.dx;
    final sy = widget.screenPos.dy;

    // デフォルトはタップ位置の右下。
    double left = sx + m;
    double top = sy + m;

    // 右端からはみ出す場合は左側に、下端からはみ出す場合は上側に反転。
    if (left + w > size.width) {
      left = sx - m - w;
    }
    if (top + h > size.height) {
      top = sy - m - h;
    }

    // 最終的に画面内に収める（負の方向にはみ出す場合も補正）。
    left = left.clamp(0.0, (size.width - w).clamp(0.0, double.infinity)).toDouble();
    top = top.clamp(0.0, (size.height - h).clamp(0.0, double.infinity)).toDouble();

    return (left, top);
  }

  @override
  Widget build(BuildContext context) {
    // 初回フレームでは実際の高さが未計測のため、推測値で配置する。
    // レイアウト後に _measureHeight が呼ばれ、実際の高さで再配置される。
    final (left, top) = _computePosition(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: left,
          top: top,
          child: RepaintBoundary(
            key: _menuKey,
            child: widget.child,
          ),
        ),
      ],
    );
  }

  /// メニューの実際の高さを計測し、必要なら位置を補正して再描画する。
  void _measureHeight() {
    final renderBox = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final actualHeight = renderBox.size.height;
    if (_measuredHeight == null ||
        (_measuredHeight! - actualHeight).abs() > 0.5) {
      setState(() {
        _measuredHeight = actualHeight;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // レイアウトが確定した後に高さを計測する。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureHeight();
    });
  }
}
