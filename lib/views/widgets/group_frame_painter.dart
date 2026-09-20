import 'dart:math';

import 'package:flutter/material.dart';

/// グループ枠（複数オブジェクトを囲む矩形枠）を描画する CustomPainter。
///
/// [rect] はキャンバス座標での枠の矩形。枠の四隅にラベルを表示でき、
/// グループ名を描画する。枠は点線の破線（dashed）で描画される。
class GroupFramePainter extends CustomPainter {
  final Rect rect;

  /// グループの表示名。
  final String title;

  /// グループの説明（description）。
  final String description;

  /// 枠の色。デフォルトは半透明の青。
  final Color color;

  /// 枠を選択しているかどうか。
  final bool isSelected;

  /// 説明を表示するかどうか（ホバー時）。
  final bool showDescription;

  GroupFramePainter({
    required this.rect,
    this.title = '',
    this.description = '',
    this.color = const Color(0x664A90D9),
    this.isSelected = false,
    this.showDescription = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 3.0 : 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // dashWidth/dashOffset はこの Flutter バージョンで未対応のため、
    // 破線を手動で描画する。矩形の周りを点線で描く。
    _drawDashedRect(canvas, paint);

    // グループ名（タイトル）を描画する。
    if (title.isNotEmpty) {
      final textSpan = TextSpan(
        text: title,
        style: TextStyle(
          color: color.withValues(alpha: 0.95),
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      // 左上隅のわずかに内側に表示する。
      final offset = Offset(
        rect.left + 6,
        rect.top - textPainter.height - 1,
      );
      textPainter.paint(canvas, offset);
    }

    // 説明（description）を描画する（ホバー時）。
    if (showDescription && description.isNotEmpty) {
      final textSpan = TextSpan(
        text: description,
        style: TextStyle(
          color: color.withValues(alpha: 0.85),
          fontSize: 16,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        maxLines: 3,
        ellipsis: '…',
      )..layout();

      // グループ名のすぐ下に表示する。
      final titleHeight = title.isNotEmpty ? 18.0 : 0.0;
      final offset = Offset(
        rect.left + 6,
        rect.top - titleHeight - textPainter.height - 1,
      );
      textPainter.paint(canvas, offset);
    }
  }

  /// 矩形を手動で破線（点線）で描画する。
  void _drawDashedRect(Canvas canvas, Paint paint) {
    const dashLength = 8.0;
    const gapLength = 4.0;

    final left = rect.left;
    final top = rect.top;
    final right = rect.right;
    final bottom = rect.bottom;

    _drawDashedLine(canvas, paint, left, top, right, top, dashLength, gapLength);
    _drawDashedLine(canvas, paint, right, top, right, bottom, dashLength, gapLength);
    _drawDashedLine(canvas, paint, right, bottom, left, bottom, dashLength, gapLength);
    _drawDashedLine(canvas, paint, left, bottom, left, top, dashLength, gapLength);
  }

  /// 2点を結ぶ線を手動で破線（点線）で描画する。
  void _drawDashedLine(
    Canvas canvas,
    Paint paint,
    double x1,
    double y1,
    double x2,
    double y2,
    double dashLength,
    double gapLength,
  ) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final length = sqrt(dx * dx + dy * dy);
    if (length <= 0) return;

    final ux = dx / length;
    final uy = dy / length;

    var distance = 0.0;
    while (distance < length) {
      final end = (distance + dashLength).clamp(0.0, length);
      canvas.drawLine(
        Offset(x1 + ux * distance, y1 + uy * distance),
        Offset(x1 + ux * end, y1 + uy * end),
        paint,
      );
      distance = end + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant GroupFramePainter oldDelegate) {
    return oldDelegate.rect != rect ||
        oldDelegate.title != title ||
        oldDelegate.description != description ||
        oldDelegate.color != color ||
        oldDelegate.isSelected != isSelected ||
        oldDelegate.showDescription != showDescription;
  }
}
