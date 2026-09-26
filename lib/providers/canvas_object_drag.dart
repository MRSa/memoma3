import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note_object.dart';
import 'canvas_state.dart';

/// [CanvasNotifier] のオブジェクトドラッグ操作
/// （位置更新 / ドラッグ終了 / キャンセル / ドラフトリセット）。
mixin CanvasObjectDrag on Notifier<CanvasState> {
  // ---------------------------------------------------------------------------
  // CanvasObjectCore が提供するメンバー（abstract 宣言）
  // ---------------------------------------------------------------------------

  /// ドラッグ中のオブジェクトのローカル座標。
  Map<String, Offset> get localDraftPositions;

  /// ドラッグ開始時のオブジェクトの位置（Undo 履歴に正しく積むため）。
  Map<String, Offset> get dragStartPositions;

  // ---------------------------------------------------------------------------
  // ドラッグ操作
  // ---------------------------------------------------------------------------

  /// オブジェクトの位置を更新する。
  /// [delta] はローカル座標空間（ズーム補正済み）での移動量。
  void updatePosition(String id, Offset delta) {
    final existing = state.getObject(id);
    if (existing == null) return;

    final base = state.objects.firstWhere((o) => o.id == id);
    final currentDraft = localDraftPositions[id] ?? base.position;
    final newPosition = Offset(
      currentDraft.dx + delta.dx,
      currentDraft.dy + delta.dy,
    );

    localDraftPositions[id] = newPosition;

    // ドラッグ中は描画専用として即座に反映する。
    final updated = base.copyWith(position: newPosition);
    final newObjects = List<NoteObject>.from(state.objects)
      ..[state.objects.indexWhere((o) => o.id == id)] = updated;

    state = CanvasState(
      objects: newObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: state.history,
      redoStack: state.redoStack,
      maxHistory: state.maxHistory,
    );
  }

  /// ドラッグを終了し、ローカルドラフト座標を実オブジェクトへ反映して
  /// Undo 履歴へ保存する。
  ///
  /// [updatePosition] はドラッグ中に [state.objects] を直接更新するため、
  /// この時点の [state] は既にドラッグ後の位置を含む。そのため、履歴に積む
  /// 「操作前の状態」は、オブジェクトの位置をドラッグ開始位置
  /// （[dragStartPositions]）に戻した状態として再構築する。これにより、
  /// Undo で正しくドラッグ前の位置へ復元される。
  ///
  /// [pushHistory] が false の場合は履歴に積まない（グループドラッグでは
  /// [endGroupDrag] が一括で履歴を積むため）。
  void endDrag(String id, {bool pushHistory = true}) {
    final draft = localDraftPositions.remove(id);
    final startPos = dragStartPositions.remove(id);
    if (draft == null) return;

    final base = state.objects.firstWhere((o) => o.id == id);
    final updated = base.copyWith(position: draft);
    final newObjects = List<NoteObject>.from(state.objects)
      ..[state.objects.indexWhere((o) => o.id == id)] = updated;

    // 履歴を積まない場合（グループドラッグの一括処理）。
    if (!pushHistory) {
      state = CanvasState(
        objects: newObjects,
        connections: state.connections,
        groupFrames: state.groupFrames,
        selectedId: state.selectedId,
        history: state.history,
        redoStack: state.redoStack,
        maxHistory: state.maxHistory,
      );
      return;
    }

    // 位置が変化していない場合は履歴に積まない（見た目が変わらないため）。
    if (startPos != null && startPos == draft) {
      state = CanvasState(
        objects: newObjects,
        connections: state.connections,
        groupFrames: state.groupFrames,
        selectedId: state.selectedId,
        history: state.history,
        redoStack: state.redoStack,
        maxHistory: state.maxHistory,
      );
      return;
    }

    // 履歴に積む「操作前の状態」を構築する。
    // state.objects は既にドラッグ後の位置を含むため、
    // 開始位置（dragStartPositions）に戻した状態を履歴に積む。
    CanvasState preDragState = state;
    if (startPos != null) {
      final preObjects = List<NoteObject>.from(state.objects);
      final idx = preObjects.indexWhere((o) => o.id == id);
      if (idx != -1) {
        preObjects[idx] = preObjects[idx].copyWith(position: startPos);
      }
      preDragState = CanvasState(
        objects: preObjects,
        connections: state.connections,
        groupFrames: state.groupFrames,
        selectedId: state.selectedId,
        history: state.history,
        redoStack: state.redoStack,
        maxHistory: state.maxHistory,
      );
    }

    final newHistory = preDragState.pushHistory(preDragState);
    state = CanvasState(
      objects: newObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: newHistory.history,
      redoStack: newHistory.redoStack,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// オブジェクトの位置を絶対座標 [position] に設定する。
  ///
  /// ドラッグ（相対移動）ではなく、一覧画面などから座標を直接指定して
  /// 移動するためのメソッド。変更がある場合のみ Undo 履歴へ積む。
  void setPosition(String id, Offset position) {
    final existing = state.getObject(id);
    if (existing == null) return;
    if (existing.position == position) return;

    final updated = existing.copyWith(position: position);
    final newObjects = List<NoteObject>.from(state.objects)
      ..[state.objects.indexWhere((o) => o.id == id)] = updated;

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

  /// ドラッグをキャンセルした場合はドラフトを破棄する。
  void cancelDrag(String id) {
    localDraftPositions.remove(id);
    dragStartPositions.remove(id);
  }

  /// ドラッグ開始時に、ローカルドラフト座標をオブジェクトの現在の
  /// 実オブジェクト座標へリセットする。
  ///
  /// 前回のドラッグや失敗したジェスチャが残したドラフトオフセットを
  /// 排除し、移動量を実位置からの相対量として安全に計算するための
  /// 処理である。これにより、画面外から移動してきたオブジェクトを触った
  /// ときにドラフトオフセットが二重に加算されて描画位置がズレる
  /// 問題を防ぐ。
  void resetDraft(String id) {
    final base = state.objects.firstWhere((o) => o.id == id);
    localDraftPositions[id] = base.position;
    // ドラッグ開始時の位置を記録する（Undo 履歴に正しく積むため）。
    dragStartPositions[id] = base.position;
  }

  /// グループの全メンバーのドラフトを開始位置へリセットする。
  ///
  /// グループ枠のドラッグ開始時に呼び、全メンバーの開始位置を
  /// [dragStartPositions] に記録する。これにより [endGroupDrag] で
  /// 各メンバーの Undo 履歴が正しく積まれる。
  void resetGroupDrafts(String groupId) {
    final frame = state.getGroupFrame(groupId);
    if (frame == null) return;
    for (final memberId in frame.memberIds) {
      final obj = state.getObject(memberId);
      if (obj == null) continue;
      localDraftPositions[memberId] = obj.position;
      dragStartPositions[memberId] = obj.position;
    }
  }

  /// 全オブジェクトをドラフト状態からクリアする。
  void clearLocalDrafts() {
    localDraftPositions.clear();
    dragStartPositions.clear();
  }
}
