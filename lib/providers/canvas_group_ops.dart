import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection.dart';
import '../models/note_object.dart';
import 'canvas_id.dart';
import 'canvas_state.dart';

/// [CanvasNotifier] のグループ枠操作（作成 / 削除 / 更新 / 追加 / 移動）。
mixin CanvasGroupOps on Notifier<CanvasState> {
  // ---------------------------------------------------------------------------
  // CanvasObjectOps が提供するメンバー（abstract 宣言）
  // ---------------------------------------------------------------------------

  /// ドラッグ中のオブジェクトのローカル座標（[moveGroup] / [endGroupDrag] 用）。
  Map<String, Offset> get localDraftPositions;

  /// ドラッグ開始時のオブジェクトの位置（[endGroupDrag] 用）。
  Map<String, Offset> get dragStartPositions;

  // ---------------------------------------------------------------------------
  // グループ枠操作
  // ---------------------------------------------------------------------------

  /// 指定したオブジェクト群を囲むグループ枠を作成する。
  ///
  /// [memberIds] のオブジェクトが1つ以上必要。既存のグループ枠と
  /// メンバーが完全に一致する場合は新しい枠を作らない。
  GroupFrame? createGroup(List<String> memberIds) {
    if (memberIds.isEmpty) return null;
    final uniqueIds = memberIds.toSet().toList();

    // 既存の枠と完全一致するか確認。
    final existing = state.groupFrames.firstWhere(
      (g) =>
          g.memberIds.length == uniqueIds.length &&
          g.memberIds.toSet().containsAll(uniqueIds.toSet()) &&
          uniqueIds.toSet().containsAll(g.memberIds.toSet()),
      orElse: () => const GroupFrame(id: '', memberIds: []),
    );
    if (existing.id.isNotEmpty) return existing;

    final newGroup = GroupFrame(
      id: generateGroupId(),
      memberIds: uniqueIds,
    );
    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: state.objects,
      connections: state.connections,
      groupFrames: [...state.groupFrames, newGroup],
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
    return newGroup;
  }

  /// グループ枠を解除する。枠に属していたオブジェクトの選択状態も解除する。
  void deleteGroup(String groupId) {
    final frame = state.getGroupFrame(groupId);
    if (frame == null) return;

    final newGroups = state.groupFrames.where((g) => g.id != groupId).toList();
    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: state.objects,
      connections: state.connections,
      groupFrames: newGroups,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// グループ枠の名称・説明・枠線色を更新する。
  void updateGroup({
    required String id,
    String? name,
    String? description,
    Color? color,
  }) {
    final existing = state.getGroupFrame(id);
    if (existing == null) return;

    final updated = existing.copyWith(
      name: name ?? existing.name,
      description: description ?? existing.description,
      color: color ?? existing.color,
    );
    final newGroups = List<GroupFrame>.from(state.groupFrames)
      ..[state.groupFrames.indexWhere((g) => g.id == id)] = updated;

    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: state.objects,
      connections: state.connections,
      groupFrames: newGroups,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// 選択中のオブジェクトを新しいグループ枠へ追加（または統合）する。
  void addToGroup({required String groupId, required String objectId}) {
    final frame = state.getGroupFrame(groupId);
    if (frame == null) return;
    if (frame.memberIds.contains(objectId)) return;

    final newMemberIds = [...frame.memberIds, objectId];
    final updated = frame.copyWith(memberIds: newMemberIds);
    final newGroups = List<GroupFrame>.from(state.groupFrames)
      ..[state.groupFrames.indexWhere((g) => g.id == groupId)] = updated;

    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: state.objects,
      connections: state.connections,
      groupFrames: newGroups,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// グループ枠を構成する全オブジェクトを、キャンバス座標空間で
  /// [delta] だけ同時に移動する。
  ///
  /// [groupId] に属していないオブジェクトは移動しない。
  void moveGroup(String groupId, Offset delta) {
    final frame = state.getGroupFrame(groupId);
    if (frame == null) return;

    final newObjects = List<NoteObject>.from(state.objects);
    for (final memberId in frame.memberIds) {
      final index = newObjects.indexWhere((o) => o.id == memberId);
      if (index == -1) continue;
      final base = state.objects[index];
      final currentDraft = localDraftPositions[memberId] ?? base.position;
      final newPosition = Offset(
        currentDraft.dx + delta.dx,
        currentDraft.dy + delta.dy,
      );
      localDraftPositions[memberId] = newPosition;
      newObjects[index] = base.copyWith(position: newPosition);
    }

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

  /// グループ枠のドラッグを終了し、全メンバーのドラフト座標を実オブジェクトへ反映する。
  ///
  /// 全メンバーのドラッグ開始位置（[dragStartPositions]）をまとめて記録し、
  /// 履歴には「全メンバーが開始位置にある状態」を 1 件だけ積む。
  /// これにより、Undo でグループ全体がドラッグ前の位置へ一括復元される。
  void endGroupDrag(String groupId) {
    final frame = state.getGroupFrame(groupId);
    if (frame == null) return;

    // 全メンバーのドラフト位置と開始位置を収集する。
    final drafts = <String, Offset>{};
    final starts = <String, Offset>{};
    var anyChanged = false;
    for (final memberId in frame.memberIds) {
      final draft = localDraftPositions[memberId];
      if (draft == null) continue;
      drafts[memberId] = draft;
      final start = dragStartPositions[memberId];
      if (start != null) {
        starts[memberId] = start;
        if (start != draft) anyChanged = true;
      }
    }
    if (drafts.isEmpty) return;

    // 全メンバーのドラフト位置を実オブジェクトへ反映する。
    final newObjects = List<NoteObject>.from(state.objects);
    for (final entry in drafts.entries) {
      final idx = newObjects.indexWhere((o) => o.id == entry.key);
      if (idx == -1) continue;
      newObjects[idx] = newObjects[idx].copyWith(position: entry.value);
    }

    // 位置が変化していない場合は履歴に積まない。
    if (!anyChanged) {
      for (final memberId in drafts.keys) {
        localDraftPositions.remove(memberId);
        dragStartPositions.remove(memberId);
      }
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

    // 履歴に積む「操作前の状態」を構築する（全メンバーを開始位置に戻す）。
    final preObjects = List<NoteObject>.from(state.objects);
    for (final entry in starts.entries) {
      final idx = preObjects.indexWhere((o) => o.id == entry.key);
      if (idx == -1) continue;
      preObjects[idx] = preObjects[idx].copyWith(position: entry.value);
    }
    final preDragState = CanvasState(
      objects: preObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: state.history,
      redoStack: state.redoStack,
      maxHistory: state.maxHistory,
    );

    final newHistory = preDragState.pushHistory(preDragState);

    // ドラフトをクリアする。
    for (final memberId in drafts.keys) {
      localDraftPositions.remove(memberId);
      dragStartPositions.remove(memberId);
    }

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
}
