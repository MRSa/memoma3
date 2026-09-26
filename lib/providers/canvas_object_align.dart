import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note_object.dart';
import 'canvas_state.dart';

/// 整列モード。
enum AlignMode {
  /// 左揃え。
  left,
  /// 右揃え。
  right,
  /// 上揃え。
  top,
  /// 下揃え。
  bottom,
  /// 等間隔（横幅 / X 方向）。
  distributeHorizontal,
  /// 等間隔（縦幅 / Y 方向）。
  distributeVertical,
}

/// [CanvasNotifier] のオブジェクト整列機能
/// （ステップ整列 / 左右上下揃え / 等間隔配置）。
mixin CanvasObjectAlign on Notifier<CanvasState> {
  // ---------------------------------------------------------------------------
  // CanvasObjectSelection が提供するメンバー（abstract 宣言）
  // ---------------------------------------------------------------------------

  /// 選択中のオブジェクトの数（[alignSelectedToStep] 用）。
  int get selectedCount;

  // ---------------------------------------------------------------------------
  // 整列機能
  // ---------------------------------------------------------------------------

  /// 座標を [step] の倍数に丸める。
  double _snap(double value, double step) {
    if (step <= 0) return value;
    return (value / step).round() * step;
  }

  /// 選択中のオブジェクトの X 座標・Y 座標を [step]（既定 10）の倍数に
  /// 揃える（オブジェクト整列機能）。
  ///
  /// 各オブジェクトの左上座標（position）を [step] の倍数に丸めることで、
  /// 配置位置を揃えられる。選択中のオブジェクトが 1 個以上必要。
  /// 変更がある場合のみ Undo 履歴へ積む。
  void alignSelectedToStep({double step = 10.0}) {
    if (selectedCount == 0) return;

    var changed = false;
    final newObjects = List<NoteObject>.from(state.objects);
    for (var i = 0; i < newObjects.length; i++) {
      final obj = newObjects[i];
      if (!obj.isSelected) continue;
      final snappedX = _snap(obj.position.dx, step);
      final snappedY = _snap(obj.position.dy, step);
      if (snappedX != obj.position.dx || snappedY != obj.position.dy) {
        newObjects[i] = obj.copyWith(
          position: Offset(snappedX, snappedY),
        );
        changed = true;
      }
    }

    if (!changed) return;

    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: newObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// 選択中のオブジェクトを [mode] で整列する。
  ///
  /// - 選択が 1 個：[alignSelectedToStep] と同じく X/Y を 10 の倍数に整列する。
  /// - 選択が 2 個以上：[AlignMode] ごとに以下のように整列する。
  ///   - [AlignMode.left]   : 一番左の左端を 10 の倍数に整えて全 X を揃える。
  ///   - [AlignMode.right]  : 一番右の右端を 10 の倍数に整えて全 X を揃える。
  ///   - [AlignMode.top]    : 一番上の上端を 10 の倍数に整えて全 Y を揃える。
  ///   - [AlignMode.bottom] : 一番下の下端を 10 の倍数に整えて全 Y を揃える。
  ///   - [AlignMode.distributeHorizontal] : 左右の端を基準に X を等間隔に配置。
  ///   - [AlignMode.distributeVertical]   : 上下の端を基準に Y を等間隔に配置。
  ///
  /// 変更がある場合のみ Undo 履歴へ積む。
  void alignSelected(AlignMode mode) {
    final selected = state.objects.where((o) => o.isSelected).toList();
    if (selected.isEmpty) return;

    // 単一選択時は従来どおり X/Y を 10 の倍数に整列する。
    if (selected.length == 1) {
      alignSelectedToStep(step: 10.0);
      return;
    }

    const step = 10.0;
    final newObjects = List<NoteObject>.from(state.objects);
    final indexById = <String, int>{};
    for (var i = 0; i < newObjects.length; i++) {
      indexById[newObjects[i].id] = i;
    }

    // 各オブジェクトのスケール反映済み矩形（rectInCanvas）を使う。
    // position は左上、width/height はスケール済みサイズ。
    switch (mode) {
      case AlignMode.left:
        final leftEdge = selected.map((o) => o.rectInCanvas().left).reduce(min);
        final target = _snap(leftEdge, step);
        for (final o in selected) {
          final i = indexById[o.id]!;
          newObjects[i] = o.copyWith(position: Offset(target, o.position.dy));
        }
        break;
      case AlignMode.right:
        final rightEdge =
            selected.map((o) => o.rectInCanvas().right).reduce(max);
        final target = _snap(rightEdge, step);
        for (final o in selected) {
          final i = indexById[o.id]!;
          final w = o.rectInCanvas().width;
          newObjects[i] = o.copyWith(
            position: Offset(target - w, o.position.dy),
          );
        }
        break;
      case AlignMode.top:
        final topEdge = selected.map((o) => o.rectInCanvas().top).reduce(min);
        final target = _snap(topEdge, step);
        for (final o in selected) {
          final i = indexById[o.id]!;
          newObjects[i] = o.copyWith(position: Offset(o.position.dx, target));
        }
        break;
      case AlignMode.bottom:
        final bottomEdge =
            selected.map((o) => o.rectInCanvas().bottom).reduce(max);
        final target = _snap(bottomEdge, step);
        for (final o in selected) {
          final i = indexById[o.id]!;
          final h = o.rectInCanvas().height;
          newObjects[i] = o.copyWith(
            position: Offset(o.position.dx, target - h),
          );
        }
        break;
      case AlignMode.distributeHorizontal:
        final sorted = [...selected]
          ..sort((a, b) => a.position.dx.compareTo(b.position.dx));
        final leftEdge = sorted.first.rectInCanvas().left;
        final rightEdge =
            sorted.map((o) => o.rectInCanvas().right).reduce(max);
        final totalWidth =
            sorted.fold<double>(0, (sum, o) => sum + o.rectInCanvas().width);
        final gap = (rightEdge - leftEdge - totalWidth) / (sorted.length - 1);
        var x = leftEdge;
        for (final o in sorted) {
          final i = indexById[o.id]!;
          final w = o.rectInCanvas().width;
          newObjects[i] = o.copyWith(position: Offset(x, o.position.dy));
          x += w + gap;
        }
        break;
      case AlignMode.distributeVertical:
        final sorted = [...selected]
          ..sort((a, b) => a.position.dy.compareTo(b.position.dy));
        final topEdge = sorted.first.rectInCanvas().top;
        final bottomEdge =
            sorted.map((o) => o.rectInCanvas().bottom).reduce(max);
        final totalHeight =
            sorted.fold<double>(0, (sum, o) => sum + o.rectInCanvas().height);
        final gap = (bottomEdge - topEdge - totalHeight) / (sorted.length - 1);
        var y = topEdge;
        for (final o in sorted) {
          final i = indexById[o.id]!;
          final h = o.rectInCanvas().height;
          newObjects[i] = o.copyWith(position: Offset(o.position.dx, y));
          y += h + gap;
        }
        break;
    }

    // 変更がある場合のみ Undo 履歴へ積む。
    var changed = false;
    for (var i = 0; i < newObjects.length; i++) {
      if (newObjects[i].position != state.objects[i].position) {
        changed = true;
        break;
      }
    }
    if (!changed) return;

    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: newObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }
}
