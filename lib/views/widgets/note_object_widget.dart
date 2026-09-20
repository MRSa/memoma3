
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../../models/note_object.dart';
import '../../../providers/canvas_provider.dart';
import 'note_shape_painter.dart';
import 'object_edit_dialog.dart';

/// 1つのノートオブジェクトを描画するウィジェット。
///
/// - [Positioned] でキャンバス上の座標に配置される。
/// - ドラッグ中に [InteractiveViewer] のパン操作と競合しないよう
///   [GestureDetector] でイベントを捕まえる。
/// - ドラッグ中はローカル表示座標を更新し、完了時に Notifier へ反映する。
class NoteObjectWidget extends ConsumerWidget {
  final NoteObject note;

  /// キャンバスの変換行列を管理するコントローラ。
  /// ドラッグ移動量を現在の拡大率で割るためする。
  final TransformationController transformationController;

  /// 接続モード中かどうか。true のときドラッグで接続線を作成する。
  final bool connectionMode;

  /// 接続モードでドラッグが終了したときに呼び出される。
  /// [targetId] はドラッグ先のオブジェクトの ID。
  final ValueChanged<String?>? onConnectionEnd;

  /// 接続モードでドラッグ中に呼び出される。ドラッグ先のキャンバス座標を報告する。
  /// 親ウィジェットがその座標に重なっているオブジェクトを検出する。
  final ValueChanged<Offset>? onConnectionDrag;

  /// 接続モードでドラッグが終了したことを親に報告する。
  final VoidCallback? onConnectionDragEnd;

  const NoteObjectWidget({
    super.key,
    required this.note,
    required this.transformationController,
    this.connectionMode = false,
    this.onConnectionEnd,
    this.onConnectionDrag,
    this.onConnectionDragEnd,
  });

  /// 画面座標をキャンバス座標空間に変換する
  Offset _screenToCanvas(Offset screenPoint) {
    final matrix = transformationController.value;
    if (matrix == Matrix4.identity()) {
      return screenPoint;
    }
    final inverse = Matrix4.tryInvert(matrix);
    if (inverse == null) {
      return screenPoint;
    }
    final transformed = inverse.transform(Vector4(screenPoint.dx, screenPoint.dy, 0, 1));
    return Offset(transformed.x, transformed.y);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(canvasNotifierProvider.notifier);

    return Positioned(
      left: note.position.dx,
      top: note.position.dy,
      width: note.size.width,
      height: note.size.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          // 接続モード時はタップで接続を開始しない（ドラッグで処理する）。
          if (connectionMode) return;
          // Ctrl+タップ：選択をトグル（複数選択）
          if (HardwareKeyboard.instance.logicalKeysPressed
              .any((k) => k == LogicalKeyboardKey.controlLeft ||
                          k == LogicalKeyboardKey.controlRight)) {
            notifier.toggleSelect(note.id);
            return;
          }
          // 通常タップ：単一選択（既存の動作を維持）
          notifier.bringToFront(note.id);
          notifier.selectObject(note.id);
        },
        onPanStart: (details) {
          // ドラッグ開始時にローカルドラフトを実位置へリセットし、
          // 前回のドラッグ等が残したドラフトオフセットの二重加算を防ぐ。
          notifier.resetDraft(note.id);
          // ドラッグ開始時に最前面へ。
          notifier.bringToFront(note.id);
          if (connectionMode) {
            // 接続モード：ドラッグ開始位置をキャンバス座標に変換して報告
            final startCanvasPoint = _screenToCanvas(details.globalPosition);
            onConnectionDrag?.call(startCanvasPoint);
            return;
          }
          notifier.selectObject(note.id);
        },
        onPanUpdate: (details) {
          // スクリーン座標の移動量の現在の拡大率で割って
          // キャンバス座標空間に変換する。
          if (connectionMode) {
            // 接続モード：現在のドラッグ位置（画面座標）をキャンバス座標に変換して報告
            final currentCanvasPoint = _screenToCanvas(details.globalPosition);
            onConnectionDrag?.call(currentCanvasPoint);
            return;
          }
          final scale = _currentScale();
          final canvasDelta = details.delta / scale;
          notifier.updatePosition(note.id, canvasDelta);
        },
        onPanEnd: (_) {
          if (connectionMode) {
            // 接続モード：ドラッグ終了を親に報告する（終点検出は親が担当）。
            onConnectionDragEnd?.call();
            return;
          }
          // ドラッグ終了時に Undo 履歴へ保存。
          notifier.endDrag(note.id);
        },
        onPanCancel: () {
          if (connectionMode) return;
          notifier.cancelDrag(note.id);
        },
        onDoubleTap: () {
          // 接続モード時はダブルタップで選択のみ、編集ダイアログは表示しない
          if (connectionMode) {
            notifier.bringToFront(note.id);
            if (!note.isSelected) notifier.selectObject(note.id);
            return;
          }
          // 通常モード：選択済みでなければ選択する（トグルで解除しない）。
          notifier.bringToFront(note.id);
          if (!note.isSelected) notifier.selectObject(note.id);
          // オブジェクト編集ダイアログを表示する。
          _openEditDialog(context, ref, note);
        },
        onLongPress: () {
          // 接続モード時は長押しで選択のみ、編集ダイアログは表示しない
          if (connectionMode) {
            notifier.bringToFront(note.id);
            if (!note.isSelected) notifier.selectObject(note.id);
            return;
          }
          // 通常モード：選択済みでなければ選択する（トグルで解除しない）。
          notifier.bringToFront(note.id);
          if (!note.isSelected) notifier.selectObject(note.id);
          // オブジェクト編集ダイアログを表示する。
          _openEditDialog(context, ref, note);
        },
        child: CustomPaint(
          size: note.size,
          painter: NoteShapePainter(
            shape: note.shape,
            color: note.color,
            isSelected: note.isSelected,
            emphasis: note.emphasis,
          ),
          child: _buildNoteContent(context),
        ),
      ),
    );
  }

  /// 現在の拡大率を取得する。
  /// [TransformationController] の行列の対角成分から読み取る。
  double _currentScale() {
    final m = transformationController.value;
    // Matrix4 の対角成分（m00, m11）からスケールを読み取る。
    // 等方スケールを仮定して平均を取る。
    final m00 = m.entry(0, 0);
    final m11 = m.entry(1, 1);
    return (m00 + m11) / 2;
  }

  /// 指定した [note] の編集ダイアログを表示する。
  ///
  /// 選択状態（selectedId）に依存せず、[note] を直接使うことで、
  /// 選択済み / 未選択のいずれの場合でも確実にダイアログが開く。
  void _openEditDialog(BuildContext context, WidgetRef ref, NoteObject note) {
    showDialog(
      context: context,
      builder: (dialogContext) => ObjectEditDialog(
        note: note,
        onShapeSelected: (shape) =>
            ref.read(canvasNotifierProvider.notifier).updateLastShape(shape),
        onSave: (updated) {
          ref
              .read(canvasNotifierProvider.notifier)
              .editObject(
                id: updated.id,
                shape: updated.shape,
                label: updated.label,
                detail: updated.detail,
                content: updated.content,
                color: updated.color,
                emphasis: updated.emphasis,
                labelColor: updated.labelColor,
                descriptionColor: updated.descriptionColor,
              );
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        },
        onCancel: () {
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        },
      ),
    );
  }

  Widget _buildNoteContent(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (note.label.isNotEmpty)
                Text(
                  note.label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    // 強調（Strong）のときはアンダーラインも引く。
                    decoration: note.emphasis == Emphasis.strong
                        ? TextDecoration.underline
                        : null,
                    color: note.labelColor ?? note.color,
                    shadows: const [
                      Shadow(
                        color: Color(0x66000000),
                        offset: Offset(1, 1),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 4),
              Text(
                note.detail,
                style: TextStyle(
                  fontSize: 14,
                  // 強調（Strong）のときは文字もボールドにする。
                  fontWeight:
                      note.emphasis == Emphasis.strong ? FontWeight.bold : null,
                  color: note.descriptionColor ?? note.color,
                  shadows: const [
                    Shadow(
                      color: Color(0x66000000),
                      offset: Offset(1, 1),
                      blurRadius: 3,
                    ),
                  ],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}