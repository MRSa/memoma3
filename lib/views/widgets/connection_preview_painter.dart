import 'package:flutter/material.dart';

/// 接続モードでドラッグ中に引かれるプレビュー線を描画する CustomPainter。
///
/// [start] と [end] はキャンバス座標。実線でなく破線で描画し、
/// ドラッグ中の一時的な接続線を表現する。
class ConnectionPreviewPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;

  ConnectionPreviewPainter({
    required this.start,
    required this.end,
    this.color = Colors.white70,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 破線で描画する（Flutter の strokeDashArray は未対応のため手動描画）。
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.0;

    final distance = (end - start).distance;
    if (distance == 0) return;
    final direction = (end - start) / distance;
    const dashLength = 8.0;
    const gapLength = 6.0;
    var drawn = 0.0;
    while (drawn < distance) {
      final dashStart = start + direction * drawn;
      final dashEnd = start + direction * (drawn + dashLength);
      canvas.drawLine(dashStart, dashEnd, paint);
      drawn += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant ConnectionPreviewPainter oldDelegate) {
    return start != oldDelegate.start || end != oldDelegate.end || color != oldDelegate.color;
  }
}
