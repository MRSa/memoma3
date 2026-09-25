import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note_object.dart';
import 'canvas_id.dart';
import 'canvas_state.dart';

/// [CanvasNotifier] のオブジェクト基本操作（追加 / 編集 / 複製 / 削除）と
/// 共有フィールド（ドラフト座標・直近追加ID・最終形状）。
mixin CanvasObjectCore on Notifier<CanvasState> {
  // ---------------------------------------------------------------------------
  // フィールド
  // ---------------------------------------------------------------------------

  /// ドラッグ中のオブジェクトに対して、描画専用のローカル座標を一時的に保持する。
  /// キーはオブジェクトの ID。ドラッグ終了時に [objects] に反映される。
  final Map<String, Offset> localDraftPositions = {};

  /// ドラッグ開始地点のキャンバス座標を一時的に保持する。
  final Map<String, Offset> dragStartCanvas = {};

  /// ドラッグ開始時のオブジェクトの位置（Undo 履歴に正しく積むため）。
  /// キーはオブジェクトの ID。[resetDraft] で設定され、
  /// [endDrag] / [cancelDrag] で削除される。
  final Map<String, Offset> dragStartPositions = {};

  /// 直近に追加されたオブジェクトの ID（UI 側で即座に選択状態を反映するため）。
  String? lastAddedId;

  /// 最後に設定された形状。新規オブジェクト作成時はこの形状をデフォルトとする。
  NoteShape lastShape = NoteShape.rectangle;

  /// 最後に設定された形状を更新する。
  void updateLastShape(NoteShape shape) {
    lastShape = shape;
  }

  // ---------------------------------------------------------------------------
  // CanvasObjectSelection が提供するメンバー（abstract 宣言）
  // ---------------------------------------------------------------------------

  /// 選択中のオブジェクトの数（[deleteSelected] 用）。
  int get selectedCount;

  // ---------------------------------------------------------------------------
  // オブジェクト操作
  // ---------------------------------------------------------------------------

  /// キャンバス上に新しいオブジェクトを追加する。
  /// 追加前 の状態を Undo 履歴へ積む。
  void addObject(NoteObject object) {
    final newHistory = state.pushHistory(state);
    final newState = CanvasState(
      objects: [...state.objects, object],
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: object.id,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
    state = newState;
    lastAddedId = object.id;
  }

  /// 選択中のオブジェクトの情報を編集する。
  ///
  /// [id] のオブジェクトの shape / label / detail / color / labelColor を
  /// 更新し、Undo 履歴へ積む。[id] が存在しない場合は何もしない。
  void editObject({
    required String id,
    NoteShape? shape,
    String? label,
    String? detail,
    String? content,
    Color? color,
    Emphasis? emphasis,
    Color? labelColor,
    Color? descriptionColor,
    double? scale,
    int? labelFontSizeLevel,
    int? descriptionFontSizeLevel,
  }) {
    final existing = state.getObject(id);
    if (existing == null) return;

    final updated = existing.copyWith(
      shape: shape,
      label: label,
      detail: detail,
      content: content,
      color: color,
      emphasis: emphasis,
      labelColor: labelColor,
      descriptionColor: descriptionColor,
      scale: scale,
      labelFontSizeLevel: labelFontSizeLevel,
      descriptionFontSizeLevel: descriptionFontSizeLevel,
    );
    // 形状が変更された場合は、次回新規作成時のデフォルト形状として保持する。
    if (shape != null) {
      lastShape = shape;
    }
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

  /// 指定したオブジェクトを最前面（リスト末尾）へ移動する。
  void bringToFront(String id) {
    final index = state.objects.indexWhere((o) => o.id == id);
    if (index == -1) return;

    final moved = state.objects[index];
    final newObjects = List<NoteObject>.from(state.objects)..removeAt(index);
    newObjects.add(moved);

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

  /// 選択中のオブジェクトを削除する（複数選択対応）。
  void deleteSelected() {
    if (selectedCount == 0) return;
    final newHistory = state.pushHistory(state);
    final newObjects = state.objects.where((o) => !o.isSelected).toList();
    state = CanvasState(
      objects: newObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: null,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// 選択中のオブジェクトを複製する（複数選択対応）。
  ///
  /// 複製先は元の位置から [offset]（デフォルト右下 20px）だけずらす。
  /// 接続線・グループ枠は引き継がない（独立した新規オブジェクトとして扱う）。
  /// 複製したオブジェクトを選択状態にし、Undo 履歴へ積む。
  void duplicateSelected({Offset offset = const Offset(20, 20)}) {
    final selected = state.objects.where((o) => o.isSelected).toList();
    if (selected.isEmpty) return;

    final newHistory = state.pushHistory(state);
    final newObjects = List<NoteObject>.from(state.objects);
    String? lastId;
    for (final o in selected) {
      final copy = o.copyWith(
        id: generateId('obj'),
        position: Offset(o.position.dx + offset.dx, o.position.dy + offset.dy),
        isSelected: true,
      );
      newObjects.add(copy);
      lastId = copy.id;
    }
    state = CanvasState(
      objects: newObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: lastId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
    lastAddedId = lastId;
  }

  /// 指定したオブジェクトを複製する（オブジェクト一覧の行単位複製用）。
  ///
  /// [duplicateSelected] と同じく、右下 20px ずらし・接続線/グループ非引き継ぎ。
  void duplicateObject(String id) {
    final existing = state.getObject(id);
    if (existing == null) return;

    final newHistory = state.pushHistory(state);
    final copy = existing.copyWith(
      id: generateId('obj'),
      position: Offset(
        existing.position.dx + 20,
        existing.position.dy + 20,
      ),
      isSelected: true,
    );
    final newObjects = [...state.objects, copy];
    state = CanvasState(
      objects: newObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: copy.id,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
    lastAddedId = copy.id;
  }

  // ---------------------------------------------------------------------------
  // 削除
  // ---------------------------------------------------------------------------

  /// 指定した [id] のオブジェクトを削除する。
  ///
  /// 同時に、そのオブジェクトに接続されていた接続線と、
  /// 含まれていたグループ枠も削除する。
  void deleteObject(String id) {
    final newObjects = state.objects.where((o) => o.id != id).toList();
    final newConnections = state.connections
        .where((c) => c.sourceId != id && c.targetId != id)
        .toList();
    final newGroups = state.groupFrames
        .where((g) => !g.memberIds.contains(id))
        .toList();
    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: newObjects,
      connections: newConnections,
      groupFrames: newGroups,
      selectedId: state.selectedId == id ? null : state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// 全オブジェクト（および接続線・グループ枠）を削除する。
  void deleteAllObjects() {
    if (state.objects.isEmpty) return;
    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: const [],
      connections: const [],
      groupFrames: const [],
      selectedId: null,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }
}
