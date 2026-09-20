
import 'package:flutter/material.dart';

import '../../models/note_object.dart';

/// 指定された [shape] に従って NoteObject の背景を描画する CustomPainter。
class NoteShapePainter extends CustomPainter {
  final NoteShape shape;
  final Color color;
  final bool isSelected;

  /// 強調レベル。標準は [Emphasis.normal]。
  final Emphasis emphasis;

  NoteShapePainter({
    required this.shape,
    required this.color,
    this.isSelected = false,
    this.emphasis = Emphasis.normal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildPath(size);

    // 強調レベルに応じた本体の描画パラメータを決定する。
    // strong: 影を強く・枠線を追加して目立たせる。
    // weak:   半透明にして目立たせない。
    final bool isStrong = emphasis == Emphasis.strong;
    final bool isWeak = emphasis == Emphasis.weak;

    // 影を描画する（本体より少し右下にオフセット、ぼかし、半透明）
    final shadowPaint = Paint()
      ..color = isStrong
          ? const Color(0x66000000)
          : (isWeak ? const Color(0x1A000000) : const Color(0x33000000))
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        isStrong ? 10.0 : 6.0,
      );
    canvas.save();
    canvas.translate(isStrong ? 3 : 2, isStrong ? 4 : 3);
    canvas.drawPath(path, shadowPaint);
    canvas.restore();

    // 本体を描画する
    final paint = Paint()
      ..color = isWeak ? color.withValues(alpha: 0.4) : color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);

    // 強調（strong）の場合、枠線でさらに目立たせる。
    if (isStrong) {
      final borderPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, borderPaint);
    }

    // 選択中のオブジェクトを四隅の緑枠（ターゲットスコープ風）で強調する。
    // 雲など複数の円が重なった形状でも視認性を損なわないよう、
    // 枠線全体ではなく四隅のみを描画する。
    if (isSelected) {
      final cornerColor = const Color(0xFF2E7D32);
      final strokeWidth = 4.0;
      final cornerLength = 28.0;
      final margin = 5.0; // オブジェクトとマーカーの間隔

      final l = -margin;
      final t = -margin;
      final r = size.width + margin;
      final b = size.height + margin;

      final topLeft = Path()
        ..moveTo(l, t + cornerLength)
        ..lineTo(l, t)
        ..lineTo(l + cornerLength, t);
      final topRight = Path()
        ..moveTo(r - cornerLength, t)
        ..lineTo(r, t)
        ..lineTo(r, t + cornerLength);
      final bottomLeft = Path()
        ..moveTo(l, b - cornerLength)
        ..lineTo(l, b)
        ..lineTo(l + cornerLength, b);
      final bottomRight = Path()
        ..moveTo(r - cornerLength, b)
        ..lineTo(r, b)
        ..lineTo(r, b - cornerLength);

      final cornerPaint = Paint()
        ..color = cornerColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(topLeft, cornerPaint);
      canvas.drawPath(topRight, cornerPaint);
      canvas.drawPath(bottomLeft, cornerPaint);
      canvas.drawPath(bottomRight, cornerPaint);
    }
  }

  Path _buildPath(Size size) {
    switch (shape) {
      case NoteShape.roundedRect:
        return Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(size.width / 2, size.height / 2),
                width: size.width,
                height: size.height,
              ),
              const Radius.circular(16),
            ),
          );
      case NoteShape.rectangle:
        return Path()
          ..addRect(
            Rect.fromCenter(
              center: Offset(size.width / 2, size.height / 2),
              width: size.width,
              height: size.height,
            ),
          );
      case NoteShape.ellipse:
        return Path()
          ..addOval(
            Rect.fromCenter(
              center: Offset(size.width / 2, size.height / 2),
              width: size.width,
              height: size.height,
            ),
          );
      case NoteShape.cloud:
        return _buildCloudPath(size);
      case NoteShape.parallelogram:
        return _buildParallelogram(size);
      case NoteShape.trapezoid:
        return _buildTrapezoid(size);
      case NoteShape.trapezium:
        return _buildTrapezium(size);
      case NoteShape.hexagon:
        return _buildHexagon(size);
      case NoteShape.pentagonLeft:
        return _buildPentagon(size, direction: _PentagonDirection.left);
      case NoteShape.pentagonRight:
        return _buildPentagon(size, direction: _PentagonDirection.right);
      case NoteShape.pentagonUp:
        return _buildPentagon(size, direction: _PentagonDirection.up);
      case NoteShape.pentagonDown:
        return _buildPentagon(size, direction: _PentagonDirection.down);
      case NoteShape.circle:
        // 円は縦横が等しい必要があるため、短い辺の長さを直径として
        // 中央に配置する（正方形のときと同様の処理）。
        final diameter = size.width < size.height ? size.width : size.height;
        final left = (size.width - diameter) / 2;
        final top = (size.height - diameter) / 2;
        return Path()
          ..addOval(
            Rect.fromLTWH(left, top, diameter, diameter),
          );
      case NoteShape.square:
        final side = size.width < size.height ? size.width : size.height;
        final left = (size.width - side) / 2;
        final top = (size.height - side) / 2;
        return Path()..addRect(Rect.fromLTWH(left, top, side, side));
    }
  }

  Path _buildCloudPath(Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;
    final rx = w / 2;
    final ry = h / 2;
    final cx = w / 2;
    final cy = h / 2;

    // 楕円を複数重ね合わせて雲の形を作る。
    path.addOval(Rect.fromCircle(center: Offset(cx - rx * 0.35, cy), radius: ry * 0.7));
    path.addOval(Rect.fromCircle(center: Offset(cx + rx * 0.3, cy - ry * 0.15), radius: ry * 0.6));
    path.addOval(Rect.fromCircle(center: Offset(cx - rx * 0.15, cy + ry * 0.25), radius: ry * 0.65));
    path.addOval(Rect.fromCircle(center: Offset(cx + rx * 0.2, cy + ry * 0.25), radius: ry * 0.55));
    path.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: ry * 0.75));
    return path;
  }

  Path _buildParallelogram(Size size) {
    final skew = size.width * 0.25;
    return Path()
      ..moveTo(skew, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - skew, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  Path _buildTrapezoid(Size size) {
    // 左右対称の台形（上が短い）。
    final topInset = size.width * 0.2;
    return Path()
      ..moveTo(topInset, 0)
      ..lineTo(size.width - topInset, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  Path _buildTrapezium(Size size) {
    // 非対称の台形（左が右より長い）。
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.7, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  Path _buildHexagon(Size size) {
    final w = size.width;
    final h = size.height;
    final insetX = w * 0.2;
    return Path()
      ..moveTo(insetX, 0)
      ..lineTo(w - insetX, 0)
      ..lineTo(w, h / 2)
      ..lineTo(w - insetX, h)
      ..lineTo(insetX, h)
      ..lineTo(0, h / 2)
      ..close();
  }

  /// 五角形（とがった方向を [direction] で指定）のパスを構築する。
  Path _buildPentagon(Size size, {required _PentagonDirection direction}) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // とがった頂点と、その反対側の2点、さらに両側の2点で五角形を作る。
    switch (direction) {
      case _PentagonDirection.left:
        // 左がとがっている。
        // 頂点: (0, h/2) → (w/2, 0) → (w, 0) → (w, h) → (w/2, h)
        return Path()
          ..moveTo(0, cy)
          ..lineTo(w * 0.5, 0)
          ..lineTo(w, 0)
          ..lineTo(w, h)
          ..lineTo(w * 0.5, h)
          ..close();
      case _PentagonDirection.right:
        // 右がとがっている。
        // 頂点: (0, 0) → (w/2, 0) → (w, h/2) → (w/2, h) → (0, h)
        return Path()
          ..moveTo(0, 0)
          ..lineTo(w * 0.5, 0)
          ..lineTo(w, cy)
          ..lineTo(w * 0.5, h)
          ..lineTo(0, h)
          ..close();
      case _PentagonDirection.up:
        // 上がとがっている。
        return Path()
          ..moveTo(cx, 0)
          ..lineTo(w, h * 0.5)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..lineTo(0, h * 0.5)
          ..close();
      case _PentagonDirection.down:
        // 下がとがっている。
        return Path()
          ..moveTo(cx, h)
          ..lineTo(w, h * 0.5)
          ..lineTo(w, 0)
          ..lineTo(0, 0)
          ..lineTo(0, h * 0.5)
          ..close();
    }
  }

  @override
  bool shouldRepaint(covariant NoteShapePainter oldDelegate) {
    return oldDelegate.shape != shape ||
        oldDelegate.color != color ||
        oldDelegate.isSelected != isSelected ||
        oldDelegate.emphasis != emphasis;
  }
}

/// 五角形のとがった方向。
enum _PentagonDirection {
  left,
  right,
  up,
  down,
}