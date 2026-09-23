import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/connection.dart';
import '../../../models/note_object.dart';
import '../../../providers/canvas_provider.dart';
import 'group_edit_dialog.dart';
import 'group_frame_painter.dart';

/// グループ枠を描画し、枠をドラッグしてグループ全体を移動するウィジェット。
///
/// 枠の四隅に配置されたハンドルで拡大/縮小も可能（将来的な拡張用）。
/// 枠上でのドラッグは、枠に属する全オブジェクトを同時に移動させる。
class GroupFrameWidget extends ConsumerStatefulWidget {
  final GroupFrame frame;
  final List<NoteObject> objects;
  final TransformationController transformationController;

  /// 枠上でのタップ時に呼び出される。
  ///
  /// グループ枠の上でも接続線を選択できるように、親側で接続線判定を行う。
  /// `true` を返すと、そのタップは接続線として処理され、
  /// グループ枠の選択はスキップされる。
  final bool Function(Offset globalPosition)? onTapDown;

  /// メンバーの外接矩形からのマージン（px）。
  ///
  /// ネストしたグループでは、外側のグループほど大きくして境界線が
  /// 重ならないようにする（親側でネスト深さに応じて指定する）。
  final double margin;

  const GroupFrameWidget({
    super.key,
    required this.frame,
    required this.objects,
    required this.transformationController,
    this.onTapDown,
    this.margin = 24.0,
  });

  @override
  ConsumerState<GroupFrameWidget> createState() => _GroupFrameWidgetState();
}

class _GroupFrameWidgetState extends ConsumerState<GroupFrameWidget> {
  bool _isSelected = false;

  /// カーソルが枠の上にあるかどうか（ホバー）。
  bool _isHovering = false;

  /// 枠の矩形を計算する。メンバーオブジェクトの外接矩形。
  Rect _computeRect() {
    final members = widget.objects.where((o) => widget.frame.memberIds.contains(o.id));
    if (members.isEmpty) return Rect.zero;

    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;

    for (final member in members) {
      final rect = member.rectInCanvas();
      left = min(left, rect.left);
      top = min(top, rect.top);
      right = max(right, rect.right);
      bottom = max(bottom, rect.bottom);
    }

    // マージンを取る（ネスト深さに応じて親側から指定される）。
    final margin = widget.margin;
    return Rect.fromLTRB(
      left - margin,
      top - margin,
      right + margin,
      bottom + margin,
    );
  }

  double _currentScale() {
    final m = widget.transformationController.value;
    return (m.entry(0, 0) + m.entry(1, 1)) / 2;
  }

  @override
  Widget build(BuildContext context) {
    final rect = _computeRect();
    if (rect == Rect.zero) return const SizedBox.shrink();

    final notifier = ref.read(canvasNotifierProvider.notifier);

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: GestureDetector(
          onTapDown: (details) {
            // 接続線に重なっている場合は、接続線を選択する（グループ選択をスキップ）。
            final handledAsConnection = widget.onTapDown?.call(details.globalPosition) ?? false;
            if (handledAsConnection) return;
            setState(() => _isSelected = true);
          },
          onTapUp: (_) {
            if (mounted) {
              setState(() => _isSelected = false);
            }
          },
          onLongPress: () {
            // 長押しでグループ編集ダイアログを表示する。
            _openEditDialog(context, ref);
          },
          onPanStart: (_) {
            // グループ移動開始。全メンバーの開始位置を記録する。
            notifier.resetGroupDrafts(widget.frame.id);
            notifier.moveGroup(widget.frame.id, Offset.zero);
          },
          onPanUpdate: (details) {
            final scale = _currentScale();
            final canvasDelta = details.delta / scale;
            notifier.moveGroup(widget.frame.id, canvasDelta);
          },
          onPanEnd: (_) {
            notifier.endGroupDrag(widget.frame.id);
            if (mounted) {
              setState(() => _isSelected = false);
            }
          },
          child: CustomPaint(
            size: Size(rect.width, rect.height),
            painter: GroupFramePainter(
              rect: Rect.fromLTWH(0, 0, rect.width, rect.height),
              title: widget.frame.name.isNotEmpty ? widget.frame.name : 'グループ',
              description: widget.frame.description,
              color: widget.frame.color,
              isSelected: _isSelected,
              showDescription: _isHovering,
            ),
          ),
        ),
      ),
    );
  }

  /// グループ編集ダイアログを表示する。
  void _openEditDialog(BuildContext context, WidgetRef ref) {
    final frame = widget.frame;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => GroupEditDialog(
        frame: frame,
        onSave: (updated) {
          ref.read(canvasNotifierProvider.notifier).updateGroup(
                id: updated.id,
                name: updated.name,
                description: updated.description,
                color: updated.color,
              );
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        },
        onCancel: () {
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        },
        onDissolve: () {
          ref.read(canvasNotifierProvider.notifier).deleteGroup(frame.id);
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                duration: Duration(milliseconds: 1500),
                content: Text('グループを解除しました')
              ),
            );
          }
        },
      ),
    );
  }
}
