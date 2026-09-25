import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection.dart';
import 'canvas_id.dart';
import 'canvas_state.dart';

/// [CanvasNotifier] の接続線操作（追加 / 更新 / 削除 / 一括接続）。
mixin CanvasConnectionOps on Notifier<CanvasState> {
  /// 2つのオブジェクトを接続する新しい接続線を追加する。
  ///
  /// 既存の線と ID が重複しないよう生成する。[sourceId] と [targetId] が
  /// 既に接続されている場合は、新しい線を追加せず既存の線を返す。
  Connection? addConnection({
    required String sourceId,
    required String targetId,
    LineType lineType = LineType.normal,
    LineShape lineShape = LineShape.straight,
  }) {
    if (sourceId == targetId) return null;

    // 同一の接続が既に存在するか確認。
    final existing = state.connections.firstWhere(
      (c) =>
          (c.sourceId == sourceId && c.targetId == targetId) ||
          (c.sourceId == targetId && c.targetId == sourceId),
      orElse: () => const Connection(id: '', sourceId: '', targetId: ''),
    );
    if (existing.id.isNotEmpty) return existing;

    final newConnection = Connection(
      id: generateConnectionId(),
      sourceId: sourceId,
      targetId: targetId,
      lineType: lineType,
      lineShape: lineShape,
    );
    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: state.objects,
      connections: [...state.connections, newConnection],
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
    return newConnection;
  }

  /// 接続線の線種・形状・色を切り替える。
  void updateConnection({
    required String id,
    LineType? lineType,
    LineShape? lineShape,
    Color? color,
  }) {
    final existing = state.getConnection(id);
    if (existing == null) return;

    final updated = existing.copyWith(
      lineType: lineType ?? existing.lineType,
      lineShape: lineShape ?? existing.lineShape,
      color: color ?? existing.color,
    );
    final newConnections = List<Connection>.from(state.connections)
      ..[state.connections.indexWhere((c) => c.id == id)] = updated;

    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: state.objects,
      connections: newConnections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// 接続線を解除する。その際、対象の線に接続されていたオブジェクトの
  /// 選択状態も解除する。
  void deleteConnection(String id) {
    final newConnections = state.connections.where((c) => c.id != id).toList();
    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: state.objects,
      connections: newConnections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// 選択中の全オブジェクトを結ぶ接続線を追加する。
  ///
  /// 選択中没有の場合は何もしない。
  void connectSelected({
    LineType lineType = LineType.normal,
    LineShape lineShape = LineShape.straight,
  }) {
    final selectedIds = state.objects.where((o) => o.isSelected).map((o) => o.id).toList();
    if (selectedIds.length < 2) return;

    final newConnections = List<Connection>.from(state.connections);
    for (var i = 0; i < selectedIds.length; i++) {
      for (var j = i + 1; j < selectedIds.length; j++) {
        final created = addConnection(
          sourceId: selectedIds[i],
          targetId: selectedIds[j],
          lineType: lineType,
          lineShape: lineShape,
        );
        if (created != null) {
          newConnections.add(created);
        }
      }
    }

    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: state.objects,
      connections: newConnections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }
}
