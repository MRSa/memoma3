import 'dart:math';
import 'package:flutter/material.dart';

import '../../models/connection.dart';

/// 2つのオブジェクトを結ぶ接続線を描画する CustomPainter。
///
/// [sourceRect] と [targetRect] はキャンバス座標（グローバル座標）での
/// オブジェクトの矩形。線はオブジェクトの境界間を結ぶ。
/// [lineShape] に応じて矢印・直線・カギ線・曲線を描画し、
/// [lineType] に応じて線種（通常/太線/点線/一点鎖線）を決定する。
class ConnectionPainter extends CustomPainter {
  final Connection connection;
  final Rect sourceRect;
  final Rect targetRect;

  /// 線の色。デフォルトは白。
  final Color color;

  /// 選択状態。選択されている場合は少し太く強調する。
  final bool isSelected;

  /// 選択中（コンテキストメニュー表示中）に使うハイライト色。
  final Color highlightColor;

  ConnectionPainter({
    required this.connection,
    required this.sourceRect,
    required this.targetRect,
    this.color = Colors.white,
    this.isSelected = false,
    this.highlightColor = const Color(0xFFFFC107),
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 選択中はハイライト色、それ以外は通常色を使う。
    final effectiveColor = isSelected ? highlightColor : color;

    final paint = Paint()
      ..color = effectiveColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = _baseStrokeWidth();

    final path = _buildPath();

    // 背景色と線の色が近くなっても線が見えるよう、影を描画する。
    // 線本体より少し右下にオフセットし、ぼかし・半透明の黒で描く。
    final shadowPaint = Paint()
      ..color = const Color(0x55000000)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = _baseStrokeWidth()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.save();
    canvas.translate(1.5, 2.0);
    _drawLineByType(canvas, path, shadowPaint);
    canvas.restore();

    // 線種に応じた描画を行う。
    _drawLineByType(canvas, path, paint);

    // 矢印の矢印頭を描画する。
    // arrow: 終点（target側）に1つ。
    // doubleArrow: 両端（source側・target側）に1つずつ。
    // reverseArrow: 始点（source側）に1つ（矢印の反対の端）。
    if (connection.lineShape == LineShape.arrow ||
        connection.lineShape == LineShape.doubleArrow ||
        connection.lineShape == LineShape.reverseArrow) {
      final (start, end) = _shortestEdgePair(sourceRect, targetRect);

      // 終点（target側）に矢印頭を描画する形状。
      final hasEndHead =
          connection.lineShape == LineShape.arrow ||
          connection.lineShape == LineShape.doubleArrow;
      // 始点（source側）に矢印頭を描画する形状。
      final hasStartHead =
          connection.lineShape == LineShape.doubleArrow ||
          connection.lineShape == LineShape.reverseArrow;

      // 矢印頭の影（線本体の影と同様にオフセット・ぼかし）。
      final headShadowPaint = Paint()
        ..color = const Color(0x55000000)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      canvas.save();
      canvas.translate(1.5, 2.0);
      if (hasEndHead) {
        canvas.drawPath(_arrowHeadAt(end, start), headShadowPaint);
      }
      if (hasStartHead) {
        canvas.drawPath(_arrowHeadAt(start, end), headShadowPaint);
      }
      canvas.restore();

      final headColor = effectiveColor.withValues(alpha: 0.9);
      final headPaint = Paint()
        ..color = headColor
        ..style = PaintingStyle.fill;

      // 終点（target側）の矢印頭：start → end の向きで終点に配置。
      if (hasEndHead) {
        canvas.drawPath(_arrowHeadAt(end, start), headPaint);
      }

      // 始点（source側）の矢印頭：end → start の向きで始点に配置。
      if (hasStartHead) {
        canvas.drawPath(_arrowHeadAt(start, end), headPaint);
      }
    }
  }

  /// 線種（実線 / 点線 / 一点鎖線）に応じてパスを描画する。
  void _drawLineByType(Canvas canvas, Path path, Paint paint) {
    switch (connection.lineType) {
      case LineType.normal:
      case LineType.thick:
        canvas.drawPath(path, paint);
        break;
      case LineType.dotted:
        _drawDashedPath(canvas, path, paint, dashLength: 2.0, gapLength: 6.0);
        break;
      case LineType.dashDot:
        _drawDashDotPath(canvas, path, paint);
        break;
    }
  }

  /// [tip] を先（矢印の先）とし、[from] 側から [tip] へ向かう方向の
  /// 矢印頭（三角形）を構築する。
  ///
  /// 矢印の先（tip）が [tip] にあり、基部（広い部分）が [from] 側
  /// （進行方向の後ろ）に配置される。
  Path _arrowHeadAt(Offset tip, Offset from) {
    final angle = atan2(tip.dy - from.dy, tip.dx - from.dx);

    // 正三角形（頂角60°、半角30°）で、高さのある矢印頭にする。
    final headLength = 20.0 + (_baseStrokeWidth() * 2);
    final halfAngle = pi / 6; // 半角30°（正三角形）

    // 基部の2点は、tip から進行方向の「後ろ」に配置する。
    final angle1 = angle + pi - halfAngle;
    final angle2 = angle + pi + halfAngle;

    final p1 = Offset(
      tip.dx + headLength * cos(angle1),
      tip.dy + headLength * sin(angle1),
    );
    final p2 = Offset(
      tip.dx + headLength * cos(angle2),
      tip.dy + headLength * sin(angle2),
    );

    return Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
  }

  /// パスに沿って破線（dash / gap の交互）を描画する。
  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dashLength,
    required double gapLength,
  }) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final segmentLength = draw ? dashLength : gapLength;
        final end = (distance + segmentLength).clamp(0.0, metric.length);
        if (draw) {
          canvas.drawPath(metric.extractPath(distance, end), paint);
        }
        distance = end;
        draw = !draw;
      }
    }
  }

  /// パスに沿って一点鎖線（長い破線 → 点 → 長い破線 → 点 …）を描画する。
  void _drawDashDotPath(Canvas canvas, Path path, Paint paint) {
    const dashLength = 12.0;
    const dotLength = 2.0;
    const gapLength = 6.0;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var phase = 0; // 0: dash, 1: gap, 2: dot, 3: gap
      while (distance < metric.length) {
        double segmentLength;
        switch (phase) {
          case 0:
            segmentLength = dashLength;
            break;
          case 1:
            segmentLength = gapLength;
            break;
          case 2:
            segmentLength = dotLength;
            break;
          default:
            segmentLength = gapLength;
        }
        final end = (distance + segmentLength).clamp(0.0, metric.length);
        if (phase == 0 || phase == 2) {
          canvas.drawPath(metric.extractPath(distance, end), paint);
        }
        distance = end;
        phase = (phase + 1) % 4;
      }
    }
  }

  double _baseStrokeWidth() {
    switch (connection.lineType) {
      case LineType.normal:
        return isSelected ? 3.0 : 2.0;
      case LineType.thick:
        return isSelected ? 7.0 : 5.0;
      case LineType.dotted:
        return isSelected ? 3.0 : 2.0;
      case LineType.dashDot:
        return isSelected ? 3.0 : 2.0;
    }
  }

  /// 接続線のパスを構築して返す（選択判定用に公開）。
  Path buildPath() => _buildPath();

  /// 線の始点と終点を計算し、Path を構築して返す。
  Path _buildPath() {
    final (start, end) = _shortestEdgePair(sourceRect, targetRect);

    switch (connection.lineShape) {
      case LineShape.straight:
        return Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy);
      case LineShape.curve:
        // 線分の中心点を制御点として、垂直方向にオフセットした二次ベジェ曲線を作る。
        final midX = (start.dx + end.dx) / 2;
        final midY = (start.dy + end.dy) / 2;
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final offset = min(60.0, (dx.abs() + dy.abs()) / 4);
        final control = Offset(
          midX + dy.clamp(-offset, offset),
          midY - dx.clamp(-offset, offset),
        );
        return Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
      case LineShape.elbow:
        return _elbowPath(start, end);
      case LineShape.arrow:
      case LineShape.doubleArrow:
      case LineShape.reverseArrow:
        return Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy);
    }
  }

  /// 直角に折れ曲がるカギ線を構築する。
  Path _elbowPath(Offset start, Offset end) {
    final path = Path();
    path.moveTo(start.dx, start.dy);

    final midX = (start.dx + end.dx) / 2;
    final midY = (start.dy + end.dy) / 2;

    // 両点が同じ軸上に近い場合は直線風に描画する。
    final absDx = (end.dx - start.dx).abs();
    final absDy = (end.dy - start.dy).abs();

    if (absDx < 20) {
      path.lineTo(end.dx, end.dy);
    } else if (absDy < 20) {
      path.lineTo(end.dx, end.dy);
    } else if (absDx >= absDy) {
      // 水平方向へ先に動く。
      path.lineTo(midX, start.dy);
      path.lineTo(midX, end.dy);
      path.lineTo(end.dx, end.dy);
    } else {
      // 垂直方向へ先に動く。
      path.lineTo(start.dx, midY);
      path.lineTo(end.dx, midY);
      path.lineTo(end.dx, end.dy);
    }
    return path;
  }

  /// 2つの矩形の辺の中心点（左・右・上・下）のうち、
  /// 最短距離となる点のペアを返す。
  (Offset, Offset) _shortestEdgePair(Rect a, Rect b) {
    final aPoints = _edgeMidpoints(a);
    final bPoints = _edgeMidpoints(b);

    Offset bestA = aPoints[0];
    Offset bestB = bPoints[0];
    double bestDist = double.infinity;

    for (final pa in aPoints) {
      for (final pb in bPoints) {
        final d = (pa - pb).distance;
        if (d < bestDist) {
          bestDist = d;
          bestA = pa;
          bestB = pb;
        }
      }
    }

    return (bestA, bestB);
  }

  /// 矩形の4辺の中心点（左・右・上・下）を返す。
  List<Offset> _edgeMidpoints(Rect rect) {
    return [
      Offset(rect.left, rect.center.dy),   // 左
      Offset(rect.right, rect.center.dy),  // 右
      Offset(rect.center.dx, rect.top),    // 上
      Offset(rect.center.dx, rect.bottom), // 下
    ];
  }

  @override
  bool shouldRepaint(covariant ConnectionPainter oldDelegate) {
    return oldDelegate.connection != connection ||
        oldDelegate.sourceRect != sourceRect ||
        oldDelegate.targetRect != targetRect ||
        oldDelegate.color != color ||
        oldDelegate.isSelected != isSelected;
  }
}
