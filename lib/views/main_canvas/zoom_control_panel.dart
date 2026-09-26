import 'package:flutter/material.dart';

import '../main_canvas_screen.dart';

/// ズーム（拡大/縮小）とリセットを行うボタンパネル。
class ZoomControlPanel extends StatelessWidget {
  final TransformationController transformationController;

  const ZoomControlPanel({super.key, required this.transformationController});

  double _currentScale() {
    final m = transformationController.value;
    return (m.entry(0, 0) + m.entry(1, 1)) / 2;
  }

  void _zoom(double factor, BuildContext context) {
    final current = _currentScale();
    final next = (current * factor).clamp(0.1, 5.0);

    // 画面中央をズームの中心にする
    final viewport = MediaQuery.of(context).size;
    final center = Offset(viewport.width / 2, viewport.height / 2);

    final m = transformationController.value;
    final tx = m.entry(0, 3);
    final ty = m.entry(1, 3);

    // 画面中央のキャンバス座標を計算
    final canvasX = (center.dx - tx) / current;
    final canvasY = (center.dy - ty) / current;

    // 画面中央が同じキャンバス座標に来るように並進を調整
    final newTx = center.dx - next * canvasX;
    final newTy = center.dy - next * canvasY;

    final newMatrix = Matrix4.identity()
      ..setEntry(0, 0, next)
      ..setEntry(1, 1, next)
      ..setEntry(0, 3, newTx)
      ..setEntry(1, 3, newTy);
    transformationController.value = newMatrix;
  }

  void _reset(BuildContext context) {
    // キャンバスの中心を画面中央に移動する
    final viewport = MediaQuery.of(context).size;
    final translateX = (viewport.width - kCanvasSize.width) / 2;
    final translateY = (viewport.height - kCanvasSize.height) / 2;
    transformationController.value = Matrix4.translationValues(translateX, translateY, 0);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '縮小',
              icon: const Icon(Icons.remove),
              onPressed: () => _zoom(0.8, context),
            ),
            IconButton(
              tooltip: '拡大',
              icon: const Icon(Icons.add),
              onPressed: () => _zoom(1.25, context),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'リセット',
              icon: const Icon(Icons.center_focus_strong),
              onPressed: () => _reset(context),
            ),
            const SizedBox(width: 4),
            // ズーム率をリアルタイム表示
            AnimatedBuilder(
              animation: transformationController,
              builder: (context, _) {
                final scale = _currentScale();
                return Text(
                  '${(scale * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
