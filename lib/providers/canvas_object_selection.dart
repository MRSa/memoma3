import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'canvas_state.dart';

/// [CanvasNotifier] のオブジェクト選択操作
/// （単一選択 / 複数選択 / 全選択 / 選択解除）。
mixin CanvasObjectSelection on Notifier<CanvasState> {
  /// オブジェクトを選択する。もう一度タップで選択解除する。
  void selectObject(String? id) {
    if (state.selectedId == id) {
      // 選択解除
      _setAllSelected(false);
      state = CanvasState(
        objects: state.objects,
        connections: state.connections,
        groupFrames: state.groupFrames,
        selectedId: null,
        history: state.history,
        redoStack: state.redoStack,
        maxHistory: state.maxHistory,
      );
      return;
    }

    _setAllSelected(false);
    if (id != null) {
      final updated = state.objects
          .map((o) => o.id == id ? o.copyWith(isSelected: true) : o)
          .toList();
      state = CanvasState(
        objects: updated,
        connections: state.connections,
        groupFrames: state.groupFrames,
        selectedId: id,
        history: state.history,
        redoStack: state.redoStack,
        maxHistory: state.maxHistory,
      );
    }
  }

  /// 指定したオブジェクトの選択状態をトグルする（複数選択用）。
  /// 既に選択されていれば解除、未選択であれば追加する。
  /// 他のオブジェクトの選択状態は維持される。
  void toggleSelect(String id) {
    final target = state.getObject(id);
    if (target == null) return;

    final updated = state.objects
        .map((o) => o.id == id ? o.copyWith(isSelected: !o.isSelected) : o)
        .toList();

    // 選択中のオブジェクトが1つもいなければ selectedId は null。
    // 1つ以上あれば、最後にトグルしたオブジェクトを selectedId として保持する。
    final count = updated.where((o) => o.isSelected).length;
    final newSelectedId = count > 0 ? id : null;

    state = CanvasState(
      objects: updated,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: newSelectedId,
      history: state.history,
      redoStack: state.redoStack,
      maxHistory: state.maxHistory,
    );
  }

  /// 選択中のオブジェクトの数を返す。
  int get selectedCount => state.objects.where((o) => o.isSelected).length;

  void _setAllSelected(bool selected) {
    final updated = state.objects.map((o) => o.copyWith(isSelected: selected)).toList();
    state = CanvasState(
      objects: updated,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: state.history,
      redoStack: state.redoStack,
      maxHistory: state.maxHistory,
    );
  }

  /// 全オブジェクトを選択する（選択モードの「全選択」用）。
  void selectAll() {
    if (state.objects.isEmpty) return;
    final updated = state.objects.map((o) => o.copyWith(isSelected: true)).toList();
    state = CanvasState(
      objects: updated,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.objects.last.id,
      history: state.history,
      redoStack: state.redoStack,
      maxHistory: state.maxHistory,
    );
  }

  /// 全選択を解除する（選択モードの「完了」・空き領域タップ用）。
  void clearSelection() {
    if (selectedCount == 0) return;
    final updated = state.objects.map((o) => o.copyWith(isSelected: false)).toList();
    state = CanvasState(
      objects: updated,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: null,
      history: state.history,
      redoStack: state.redoStack,
      maxHistory: state.maxHistory,
    );
  }
}
