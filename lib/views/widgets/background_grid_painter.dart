import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../models/background_config.dart';

/// キャンバス背景にグリッド（罫線 / ドット）を描画するウィジェット。
///
/// [InteractiveViewer] の**外側**（ビューポート固定の body Stack）に配置し、
/// [TransformationController] の変換行列から「表示中のキャンバス領域」を
/// 逆算して、その範囲のグリッドのみを描画する。これによりキャンバス
/// （50000x50000）全体を描画せず、パン/ズームしても常に軽量に描画できる。
///
/// グリッドはキャンバス座標に固定されているため、パン/ズームしても
/// オブジェクトに対して相対的に正しい位置に描画される。描画はビューポート
/// 座標系で行うため、各グリッド点をキャンバス→ビューポート変換行列で
/// 変換して描画する。
class BackgroundGridOverlay extends StatefulWidget {
  final TransformationController transformationController;
  final BackgroundConfig config;

  const BackgroundGridOverlay({
    super.key,
    required this.transformationController,
    required this.config,
  });

  @override
  State<BackgroundGridOverlay> createState() => _BackgroundGridOverlayState();
}

class _BackgroundGridOverlayState extends State<BackgroundGridOverlay> {
  @override
  void initState() {
    super.initState();
    widget.transformationController.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(BackgroundGridOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transformationController != widget.transformationController) {
      oldWidget.transformationController.removeListener(_onTransformChanged);
      widget.transformationController.addListener(_onTransformChanged);
    }
  }

  @override
  void dispose() {
    widget.transformationController.removeListener(_onTransformChanged);
    super.dispose();
  }

  void _onTransformChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.config.hasGrid) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        final matrix = widget.transformationController.value;
        final inverse = Matrix4.tryInvert(matrix);
        if (inverse == null) return const SizedBox.shrink();

        // ビューポートの4角をキャンバス座標に変換し、表示領域を求める。
        final topLeft = inverse.transform(Vector4(0, 0, 0, 1));
        final topRight = inverse.transform(Vector4(viewport.width, 0, 0, 1));
        final bottomLeft = inverse.transform(Vector4(0, viewport.height, 0, 1));
        final bottomRight =
            inverse.transform(Vector4(viewport.width, viewport.height, 0, 1));
        final xs = [topLeft.x, topRight.x, bottomLeft.x, bottomRight.x];
        final ys = [topLeft.y, topRight.y, bottomLeft.y, bottomRight.y];
        final minX = xs.reduce((a, b) => a < b ? a : b);
        final minY = ys.reduce((a, b) => a < b ? a : b);
        final maxX = xs.reduce((a, b) => a > b ? a : b);
        final maxY = ys.reduce((a, b) => a > b ? a : b);

        // 表示領域（キャンバス座標）のグリッドを描画する。
        // このウィジェットは InteractiveViewer の外側（ビューポート座標系）
        // にあるため、各グリッド点をキャンバス→ビューポート変換行列で
        // 変換して描画する。
        return CustomPaint(
          size: viewport,
          painter: _GridPainter(
            config: widget.config,
            visibleRect: Rect.fromLTRB(minX, minY, maxX, maxY),
            matrix: matrix,
          ),
        );
      },
    );
  }
}

/// 表示領域（キャンバス座標）のグリッドのみを描画する [CustomPainter]。
///
/// この Painter は [InteractiveViewer] の外側（ビューポート座標系）で
/// 描画されるため、キャンバス座標の各グリッド点を [matrix]
/// （キャンバス→ビューポート変換）で変換して描画する。
class _GridPainter extends CustomPainter {
  final BackgroundConfig config;
  final Rect visibleRect;
  final Matrix4 matrix;

  _GridPainter({
    required this.config,
    required this.visibleRect,
    required this.matrix,
  });

  /// キャンバス座標をビューポート座標に変換する。
  Offset _toViewport(double x, double y) {
    final v = matrix.transform(Vector4(x, y, 0, 1));
    return Offset(v.x, v.y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final color = config.gridColor.withValues(alpha: config.gridOpacity);
    final spacing = config.gridSpacing;
    if (spacing <= 0) return;

    // ウィジェット領域（body）の外側にはみ出すグリッド線（トップアクションバー
    // の領域など）を描画しないよう、描画範囲をウィジェットサイズでクリップする。
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // 表示領域を [spacing] の倍数に丸めて、描画するグリッド線の範囲を求める。
    final startX = (visibleRect.left / spacing).floor() * spacing;
    final endX = (visibleRect.right / spacing).ceil() * spacing;
    final startY = (visibleRect.top / spacing).floor() * spacing;
    final endY = (visibleRect.bottom / spacing).ceil() * spacing;

    switch (config.gridType) {
      case GridType.lines:
        _paintLines(canvas, color, spacing, startX, endX, startY, endY);
      case GridType.dots:
        _paintDots(canvas, color, spacing, startX, endX, startY, endY);
      case GridType.none:
        break;
    }

    canvas.restore();
  }

  void _paintLines(
    Canvas canvas,
    Color color,
    double spacing,
    double startX,
    double endX,
    double startY,
    double endY,
  ) {
    final paint = ui.Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = ui.PaintingStyle.stroke;

    for (double x = startX; x <= endX; x += spacing) {
      canvas.drawLine(_toViewport(x, startY), _toViewport(x, endY), paint);
    }
    for (double y = startY; y <= endY; y += spacing) {
      canvas.drawLine(_toViewport(startX, y), _toViewport(endX, y), paint);
    }
  }

  void _paintDots(
    Canvas canvas,
    Color color,
    double spacing,
    double startX,
    double endX,
    double startY,
    double endY,
  ) {
    final radius = 1.5;
    final paint = ui.Paint()..color = color;

    for (double x = startX; x <= endX; x += spacing) {
      for (double y = startY; y <= endY; y += spacing) {
        canvas.drawCircle(_toViewport(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) {
    return oldDelegate.config.gridType != config.gridType ||
        oldDelegate.config.gridSpacing != config.gridSpacing ||
        oldDelegate.config.gridColor != config.gridColor ||
        oldDelegate.config.gridOpacity != config.gridOpacity ||
        oldDelegate.visibleRect != visibleRect ||
        oldDelegate.matrix != matrix;
  }
}
